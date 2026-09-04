#!/bin/bash
#
# chequeo_bateria.sh - Watchdog reactivo de batería, corre cada 5 min por
# cron. Equivalente al de la v1.1 (que usaba el % de la PiJuice) pero acá
# el corte es por VOLTAJE puro del INA219 -- no por ningún porcentaje
# estimado. Ver la nota completa en config/config_general.txt (por qué el
# umbral es voltaje y no %, justificación del valor, y el plan pendiente
# de la curva de % para logs/dashboard que NO participa de este chequeo).

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"
export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"

CONFIG_GENERAL="$BASE_PATH/config/config_general.txt"
DRIVE_PATH=$(awk -F'=' '/^DRIVE_PATH=/{print $2}' "$CONFIG_GENERAL" | tr -d '\r')

VENTANA_ACTIVA=$(awk -F'=' '/^VENTANA_ACTIVA=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')

# Sin ventana activa no hay nada que proteger -- la Pi va a estar apagada
# la mayor parte de ese tiempo igual (ver circuito RTC+latch), y no tiene
# sentido gastar una lectura I2C en vano.
if [ "$VENTANA_ACTIVA" = "NONE" ]; then
	exit 0
fi

UMBRAL=$(awk -F'=' '/^UMBRAL_BATERIA_V=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')

# timeout defensivo: si el bus I2C se traba (paso una vez, el 3/9, y
# encolgo el sistema entero hasta un power-cycle completo), esta lectura
# no se tiene que quedar esperando para siempre -- se corta a los 12s, se
# loguea, y el proximo chequeo de cron (5 min despues) lo vuelve a intentar
# solo. 12s (no 10) porque registrar_bateria.py hace DOS lecturas (con
# carga + sin carga), un poco mas que antes.
#
# registrar_bateria.py hace la lectura dual (con/sin carga MPPT) y loguea
# las dos a log_bateria.txt para caracterizar ambos regimenes -- pero solo
# imprime por stdout la de SIN carga, que es la unica que participa de la
# decision de seguridad de aca abajo (ver justificacion en
# config/config_general.txt).
LECTURA=$(timeout 12 python3 "$BASE_PATH/python/registrar_bateria.py" 2>&1)
CODIGO=$?
if [ $CODIGO -eq 124 ]; then
	python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: chequeo_bateria -- lectura del INA219 colgada, cortada a los 12s (posible bus I2C trabado)"
	exit 1
elif [ $CODIGO -ne 0 ]; then
	python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: chequeo_bateria no pudo leer el INA219 -- $LECTURA"
	exit 1
fi

VOLTAJE=$(echo "$LECTURA" | grep -oP 'Voltaje \(pack\): \K[0-9.]+')

if [ -z "$VOLTAJE" ]; then
	python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: chequeo_bateria no pudo parsear la lectura del INA219: $LECTURA"
	exit 1
fi

# Comparacion de punto flotante -- bash no la hace nativamente.
BAJO_UMBRAL=$(awk -v v="$VOLTAJE" -v u="$UMBRAL" 'BEGIN { print (v < u) ? "1" : "0" }')

if [ "$BAJO_UMBRAL" = "1" ]; then
	sed -i "s/^CIERRE_FORZADO=.*/CIERRE_FORZADO=TRUE/" "$CONFIG_GENERAL"
	python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: bateria en ${VOLTAJE}V, por debajo del umbral (${UMBRAL}V) -- cierre forzado marcado"
fi

# Subida del log de caracterizacion de bateria a Drive, best-effort -- va
# DESPUES de la decision de seguridad de arriba a proposito, para que un
# problema de red/Drive nunca demore ni afecte esa decision. Si falla
# (sin wifi en este instante, Drive caido, lo que sea) no pasa nada, se
# reintenta solo en la proxima corrida del cron, 5 min despues.
timeout 30 rclone copy "$BASE_PATH/log_bateria.txt" "gdrive:$DRIVE_PATH/" 2>/dev/null

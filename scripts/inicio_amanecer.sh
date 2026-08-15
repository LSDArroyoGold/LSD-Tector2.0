#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"
export HOME="$USER_HOME"

CONFIG_HORARIOS="$BASE_PATH/config/config_horarios.txt"
CONFIG_GENERAL="$BASE_PATH/config/config_general.txt"
DRIVE_PATH=$(awk -F'=' '/^DRIVE_PATH=/{print $2}' "$CONFIG_GENERAL" | tr -d '\r')

HORARIO=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

if [ "$HORA_ACTUAL" = "$HORARIO_DELAY" ]; then

	# PENDIENTE: chequeo de bateria por INA219. La v1.1 calculaba aca un
	# umbral predictivo (formula CONSUMO_W/CAPACIDAD_MAH/VOLTAJE_BATERIA/
	# MARGEN_SEGURIDAD) via la API de PiJuice, y cancelaba la ventana si el
	# nivel no alcanzaba. Sin PiJuice y sin el INA219 armado todavia, no hay
	# forma de medir bateria: la ventana arranca siempre. Cuando el INA219
	# este instalado, retomar el chequeo aca (o, mejor, migrar al esquema de
	# watchdog reactivo de la v1.1 -- ver chequeo_bateria.sh -- en vez de
	# volver al corte predictivo). El umbral a usar ya esta definido --
	# UMBRAL_BATERIA_V=6.9 (ver config/config_general.txt) -- falta unicamente
	# el hardware y la lectura del sensor.

	FIN_ESPERADO=$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
	python3 "$BASE_PATH/python/log_sistema.py" INICIO amanecer $FIN_ESPERADO

	sudo nmcli radio wifi on
	INTENTOS=0
	until ping -c 1 google.com &>/dev/null || [ $INTENTOS -ge 6 ]; do
		sleep 5
		INTENTOS=$((INTENTOS + 1))
	done

	if ! ping -c 1 google.com &>/dev/null; then
		echo "Sin conexión, abortando"
		sudo nmcli radio wifi off
		exit 1
	fi

	rclone copy "$BASE_PATH/log_sistema.txt" "gdrive:$DRIVE_PATH/"

	bash "$BASE_PATH/scripts/actualizar_repo.sh"

	sudo nmcli radio wifi off
	sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"
fi

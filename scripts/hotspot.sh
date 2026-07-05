#!/bin/bash

# Autodeteccion de rutas del proyecto
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

# Deteccion robusta del usuario real y su home (incluso si el script corre con sudo)
REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

export RCLONE_CONFIG="$USER_HOME/.config/rclone/rclone.conf"
export HOME="$USER_HOME"

LOG_PATH="$BASE_PATH/log_sistema.txt"
CONFIG_PATH="$BASE_PATH/config/config_general.txt"
CONFIG_HORARIOS="$BASE_PATH/config/config_horarios.txt"

DRIVE_PATH=$(awk -F'=' '/^DRIVE_PATH=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
HOTSPOT_SSID=$(awk -F'=' '/^HOTSPOT_SSID=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
HOTSPOT_PASSWORD=$(awk -F'=' '/^HOTSPOT_PASSWORD=/{print $2}' "$CONFIG_PATH" | tr -d '\r')

log() {
    python3 "$BASE_PATH/python/log_sistema.py" MSG "$1"
}

FIRST_START=$(awk -F'=' '/FIRST_START/{print $2}' "$CONFIG_PATH" | tr -d '\r')

sleep 15

# Chequear si fue activado por botón
BUTTON_FLAG=$(python3 -c "
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(24, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
val = GPIO.input(24)
GPIO.cleanup()
print(val)
")

if [ "$FIRST_START" != "TRUE" ] && [ "$BUTTON_FLAG" != "1" ]; then
    exit 0
fi

if [ "$BUTTON_FLAG" = "1" ]; then
python3 -c "
import RPi.GPIO as GPIO
GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(25, GPIO.OUT)
GPIO.output(25, GPIO.LOW)
import time; time.sleep(0.1)
GPIO.output(25, GPIO.HIGH)
GPIO.cleanup()
"
    sed -i 's/FIRST_START=.*/FIRST_START=TRUE/' "$CONFIG_PATH"
    FIRST_START="TRUE"
fi

if [ "$FIRST_START" != "TRUE" ]; then
    exit 0
fi

log "Modo primer arranque: activando hotspot"

sudo rfkill unblock wifi
sleep 2
sudo nmcli radio wifi on
sleep 2

levantar_hotspot() {
    sudo ip addr flush dev wlan0
    sleep 1
    sudo pkill dnsmasq 2>/dev/null
    sleep 2
    sudo nmcli device wifi hotspot ifname wlan0 ssid "$HOTSPOT_SSID" password "$HOTSPOT_PASSWORD" con-name Hotspot
    sleep 3
    sudo nmcli connection modify Hotspot ipv4.addresses 192.168.4.1/24 ipv4.method shared
    sudo nmcli connection up Hotspot
}

levantar_hotspot
if [ $? -ne 0 ]; then
    log "Primer intento fallido. Reintentando hotspot..."
    sleep 5
    levantar_hotspot
    if [ $? -ne 0 ]; then
        log "Error: no se pudo levantar el hotspot después de dos intentos."
        exit 1
    fi
fi


sleep 5

IP_HOTSPOT=$(ip addr show wlan0 | grep -oP 'inet \K[\d.]+')
log "Hotspot activo en IP: $IP_HOTSPOT"

# Lanzar portal y capturar exit code
sudo python3 "$BASE_PATH/python/portal_configuracion.py"
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then
    log "Conexión fallida. Hotspot reactivado, esperando nuevas credenciales."
    exit 1
fi

# --- CONEXION EXITOSA ---

# Sincronizar hora
sudo systemctl restart systemd-timesyncd
sleep 5
python3 "$BASE_PATH/python/sync_pijuice_rtc.py"
log "RTC sincronizado."

log "Conexión WiFi exitosa."

UBICACION=$(curl -s ipinfo.io/json)
LAT=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[0])")
LON=$(echo $UBICACION | python3 -c "import sys,json; coords=json.load(sys.stdin)['loc'].split(','); print(coords[1])")
sed -i "s/LAT=.*/LAT=$LAT/" "$CONFIG_PATH"
sed -i "s/LON=.*/LON=$LON/" "$CONFIG_PATH"
log "Ubicación detectada: $LAT, $LON"

# Marcar FIRST_START = FALSE
sed -i 's/FIRST_START=TRUE/FIRST_START=FALSE/' "$CONFIG_PATH"

bash "$BASE_PATH/scripts/auto_sync_horarios.sh"
rclone copy "$CONFIG_HORARIOS" "gdrive:$DRIVE_PATH/"

# Calcular próxima ventana (la más cercana a futuro)
HORA_ACTUAL_MIN=$(date +%H%M | sed 's/^0*//')
INICIO_AMANECER=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r:')
INICIO_ATARDECER=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r:')

INICIO_AMANECER_MIN=$(echo "$INICIO_AMANECER" | sed 's/^0*//')
INICIO_ATARDECER_MIN=$(echo "$INICIO_ATARDECER" | sed 's/^0*//')

if [ "$INICIO_AMANECER_MIN" -gt "$HORA_ACTUAL_MIN" ]; then
    HORA_WAKE=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
    log "Próxima ventana: amanecer a las $HORA_WAKE"
elif [ "$INICIO_ATARDECER_MIN" -gt "$HORA_ACTUAL_MIN" ]; then
    HORA_WAKE=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
    log "Próxima ventana: atardecer a las $HORA_WAKE"
else
    HORA_WAKE=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
    log "Ambas ventanas pasaron hoy. Próxima ventana: amanecer mañana a las $HORA_WAKE"
fi

# Programar alarma y apagar
python3 "$BASE_PATH/python/set_wake_pijuice.py" $HORA_WAKE
log "Alarma programada para $HORA_WAKE. Apagando."

# Subir log a Drive
rclone copy "$LOG_PATH" "gdrive:$DRIVE_PATH/"
sudo nmcli radio wifi off

sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"

python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
"
sudo poweroff

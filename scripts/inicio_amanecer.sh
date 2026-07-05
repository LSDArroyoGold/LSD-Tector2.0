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

	UMBRAL=$(python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)

CONSUMO_W='$(awk -F'=' '/CONSUMO_W/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')'

AUTO_SYNC='$(awk -F'=' '/AUTO_SYNC/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')'
if AUTO_SYNC == 'ON':
	duracion_h = '$(awk -F'=' '/DURACION_AMANECER_SYNC/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')'
else:
	from datetime import datetime
	t_inicio = datetime.strptime('$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')', '%H:%M')
	t_fin = datetime.strptime('$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')', '%H:%M')
	duracion_h = (t_fin - t_inicio).seconds / 3600

CONSUMO_WH = float(CONSUMO_W) * duracion_h
CAPACIDAD_MAH = $(awk -F'=' '/CAPACIDAD_MAH/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')
VOLTAJE = $(awk -F'=' '/VOLTAJE_BATERIA/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')
MARGEN = $(awk -F'=' '/MARGEN_SEGURIDAD/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')

capacidad_wh = (CAPACIDAD_MAH/1000)*VOLTAJE
umbral = (CONSUMO_WH/capacidad_wh)*100*MARGEN
print(int(umbral))
")

	NIVEL=$(python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.status.GetChargeLevel()['data'])
")

	if [ "$NIVEL" -lt "$UMBRAL" ]; then

		python3 "$BASE_PATH/python/log_sistema.py" CANCELADA amanecer
		sudo nmcli radio wifi on
		INTENTOS=0
		until ping -c 1 google.com &>/dev/null || [ $INTENTOS -ge 6 ]; do
			sleep 5
			INTENTOS=$((INTENTOS + 1))
		done

		if ping -c 1 google.com &>/dev/null; then
			rclone copy "$BASE_PATH/log_sistema.txt" "gdrive:$DRIVE_PATH/"
		fi

		sudo nmcli radio wifi off

		sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"

		HORA_WAKE=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d '\r')
		python3 "$BASE_PATH/python/set_wake_pijuice.py" $HORA_WAKE
		python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
"
		sudo poweroff
	else
		python3 "$BASE_PATH/python/log_sistema.py" INICIO amanecer
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
		sudo nmcli radio wifi off

		sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"
	fi
fi

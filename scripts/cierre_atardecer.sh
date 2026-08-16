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

HORARIO=$(awk -F'=' '/FIN_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
HORA_ACTUAL=$(date +%H:%M)

if [ "$HORA_ACTUAL" = "$HORARIO" ]; then

	sudo nmcli radio wifi on

	INTENTOS=0
	until ping -c 1 google.com &>/dev/null || [ $INTENTOS -ge 6 ]; do
		sleep 5
		INTENTOS=$((INTENTOS + 1))
	done

	if ! ping -c 1 google.com &>/dev/null; then
		sudo nmcli radio wifi off

		find "$USER_HOME/BirdSongs/Extracted/By_Date/" -name "*.png" -delete
    	rm -rf "$USER_HOME/BirdSongs/Extracted/Charts/"*

		HORA_INICIO=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
        HORA_FIN=$(awk -F'=' '/FIN_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
        DETECCIONES=$(find "$USER_HOME/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/" -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)

        HORA_WAKE=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d '\r')
        PROXIMA_VENTANA=$(echo "$HORA_WAKE" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')
        python3 "$BASE_PATH/python/log_sistema.py" SIN_CONEXION atardecer $PROXIMA_VENTANA $DETECCIONES

        bash "$BASE_PATH/scripts/auto_sync_horarios.sh"

        python3 "$BASE_PATH/python/set_wake_rtc.py" $HORA_WAKE

        sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"

		# PENDIENTE: ver nota de cierre_amanecer.sh sobre el apagado
		# (SetPowerOff + poweroff de la v1.1) -- sigue sin circuito de corte.
	fi

	sudo systemctl restart systemd-timesyncd
	sleep 5

	python3 "$BASE_PATH/python/sync_rtc.py"

	find "$USER_HOME/BirdSongs/Extracted/By_Date/" -name "*.png" -delete
	rm -rf "$USER_HOME/BirdSongs/Extracted/Charts/"*

	rclone copy "$USER_HOME/BirdSongs/Extracted/By_Date/" "gdrive:$DRIVE_PATH/Detecciones" --include "*.mp3"

	HORA_INICIO=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
	HORA_FIN=$(awk -F'=' '/FIN_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
	DETECCIONES=$(find "$USER_HOME/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/" -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)

	bash "$BASE_PATH/scripts/auto_sync_horarios.sh"

	rclone copy "gdrive:$DRIVE_PATH/config_horarios.txt" "$BASE_PATH/config/"

	HORA_WAKE=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d '\r')
	PROXIMA_VENTANA=$(echo "$HORA_WAKE" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

	python3 "$BASE_PATH/python/log_sistema.py" FIN atardecer $PROXIMA_VENTANA $DETECCIONES

	rclone copy "$BASE_PATH/log_sistema.txt" "gdrive:$DRIVE_PATH/"
	bash "$BASE_PATH/scripts/generar_log_reciente.sh"

	sudo nmcli radio wifi off

	python3 "$BASE_PATH/python/set_wake_rtc.py" $HORA_WAKE

	# PENDIENTE: ver nota de cierre_amanecer.sh sobre el apagado (SetPowerOff
	# + poweroff de la v1.1) -- sigue sin circuito de corte.

	echo "Cierre atardecer completado a las $HORA_ACTUAL"
fi

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

HORARIO=$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
HORA_ACTUAL=$(date +%H:%M)
CIERRE_FORZADO=$(awk -F'=' '/^CIERRE_FORZADO=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')
VENTANA_ACTIVA=$(awk -F'=' '/^VENTANA_ACTIVA=/{print $2}' "$CONFIG_GENERAL" | tr -d ' \r')

# Cierra por horario normal, O antes de tiempo si chequeo_bateria.sh marco
# CIERRE_FORZADO (bateria por debajo de UMBRAL_BATERIA_V) durante esta
# misma ventana -- el chequeo de VENTANA_ACTIVA evita que un
# CIERRE_FORZADO viejo de la ventana atardecer dispare aca por error.
if [ "$HORA_ACTUAL" = "$HORARIO" ] || { [ "$CIERRE_FORZADO" = "TRUE" ] && [ "$VENTANA_ACTIVA" = "amanecer" ]; }; then

	sed -i "s/^VENTANA_ACTIVA=.*/VENTANA_ACTIVA=NONE/" "$CONFIG_GENERAL"
	sed -i "s/^CIERRE_FORZADO=.*/CIERRE_FORZADO=FALSE/" "$CONFIG_GENERAL"

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

		HORA_INICIO=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
		HORA_FIN=$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
		DETECCIONES=$(find "$USER_HOME/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/" -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)

		HORA_WAKE=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d '\r')
		PROXIMA_VENTANA=$(echo "$HORA_WAKE" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')
		python3 "$BASE_PATH/python/log_sistema.py" SIN_CONEXION amanecer $PROXIMA_VENTANA $DETECCIONES

		bash "$BASE_PATH/scripts/auto_sync_horarios.sh"

		timeout 15 python3 "$BASE_PATH/python/set_wake_rtc.py" $HORA_WAKE
		ALARMA_ARMADA=$?

		sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"

		# Solo apagar si la alarma quedo confirmada -- si no, la Pi quedaria
		# sin forma de despertar sola (el circuito de corte no distingue
		# "alarma armada" de "alarma vieja/sin armar", asi que es este
		# script el que tiene que frenar el apagado si algo fallo).
		if [ "$ALARMA_ARMADA" -eq 0 ]; then
			sudo poweroff
		else
			python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: alarma RTC no se pudo armar, NO se apaga (quedaria sin forma de despertar)"
		fi
	fi

	sudo systemctl restart systemd-timesyncd
	sleep 5

	timeout 10 python3 "$BASE_PATH/python/sync_rtc.py"

	# Si BirdNET-Pi esta instalado, confirmar que el pipeline de grabacion y
	# analisis sigue vivo. systemd ya reinicia estos servicios solos si se
	# caen (Restart=always), asi que esto no es para arreglarlos: es para
	# que quede registrado en el log si algo no arranco o quedo en loop de
	# reinicio, en vez de enterarse recien al volver al campo por la falta
	# de detecciones.
	if systemctl list-unit-files birdnet_analysis.service &>/dev/null; then
		SERVICIOS_CAIDOS=""
		for SERVICIO in birdnet_recording.service birdnet_analysis.service; do
			systemctl is-active --quiet "$SERVICIO" || SERVICIOS_CAIDOS="$SERVICIOS_CAIDOS $SERVICIO"
		done
		if [ -n "$SERVICIOS_CAIDOS" ]; then
			python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: servicios de BirdNET-Pi caidos:$SERVICIOS_CAIDOS"
		fi
	fi

	# Mismo chequeo que arriba, para el motor propio (birdnet-lsd) cuando
	# es el que esta instalado en vez de BirdNET-Pi stock.
	if systemctl list-unit-files birdnet-lsd.service &>/dev/null; then
		systemctl is-active --quiet birdnet-lsd.service || \
			python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: birdnet-lsd.service caido"
	fi

	find "$USER_HOME/BirdSongs/Extracted/By_Date/" -name "*.png" -delete
	rm -rf "$USER_HOME/BirdSongs/Extracted/Charts/"*

	rclone copy "$USER_HOME/BirdSongs/Extracted/By_Date/" "gdrive:$DRIVE_PATH/Detecciones" --include "*.mp3"

	HORA_INICIO=$(awk -F'=' '/INICIO_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
	HORA_FIN=$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r' | tr -d ':')
	DETECCIONES=$(find "$USER_HOME/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/" -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)

	bash "$BASE_PATH/scripts/auto_sync_horarios.sh"

	rclone copy "gdrive:$DRIVE_PATH/config_horarios.txt" "$BASE_PATH/config/"

	HORA_WAKE=$(awk -F'=' '/INICIO_ATARDECER/{print $2}' "$CONFIG_HORARIOS" | tr -d '\r')
	PROXIMA_VENTANA=$(echo "$HORA_WAKE" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

	python3 "$BASE_PATH/python/log_sistema.py" FIN amanecer $PROXIMA_VENTANA $DETECCIONES

	rclone copy "$BASE_PATH/log_sistema.txt" "gdrive:$DRIVE_PATH/"
	bash "$BASE_PATH/scripts/generar_log_reciente.sh"

	sudo nmcli radio wifi off

	sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"

	timeout 15 python3 "$BASE_PATH/python/set_wake_rtc.py" $HORA_WAKE
	ALARMA_ARMADA=$?

	echo "Cierre amanecer completado a las $HORA_ACTUAL"

	# Ver nota equivalente mas arriba en este mismo archivo sobre por que
	# el apagado depende de que la alarma haya quedado armada.
	if [ "$ALARMA_ARMADA" -eq 0 ]; then
		sudo poweroff
	else
		python3 "$BASE_PATH/python/log_sistema.py" MSG "ALERTA: alarma RTC no se pudo armar, NO se apaga (quedaria sin forma de despertar)"
	fi
fi

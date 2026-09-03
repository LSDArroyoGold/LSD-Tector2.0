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

	# Reset defensivo: si el cierre anterior no llego a resetear estos
	# flags (crash, corte de energia a mitad de ventana), no arrancar ya
	# con CIERRE_FORZADO=TRUE puesto de una ventana vieja.
	sed -i "s/^VENTANA_ACTIVA=.*/VENTANA_ACTIVA=NONE/" "$CONFIG_GENERAL"
	sed -i "s/^CIERRE_FORZADO=.*/CIERRE_FORZADO=FALSE/" "$CONFIG_GENERAL"

	FIN_ESPERADO=$(awk -F'=' '/FIN_AMANECER/{print $2}' "$CONFIG_HORARIOS" | tr -d ' \r')
	python3 "$BASE_PATH/python/log_sistema.py" INICIO amanecer $FIN_ESPERADO
	sed -i "s/^VENTANA_ACTIVA=.*/VENTANA_ACTIVA=amanecer/" "$CONFIG_GENERAL"

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
	bash "$BASE_PATH/scripts/generar_log_reciente.sh"

	bash "$BASE_PATH/scripts/actualizar_repo.sh"

	if systemctl list-unit-files birdnet-lsd.service &>/dev/null; then
		# Motor propio (birdnet-lsd) instalado en este dispositivo: en vez
		# de actualizar_modelo.sh (retirado del repo birdnet-lsd el 29/08,
		# TensorFlow/modelo reentrenado reemplazados por TectorNet), se usa
		# actualizar_birdnet_lsd.sh -- hace git pull + reinstala si cambiaron
		# dependencias + reinicia con chequeo de salud (revierte solo si el
		# commit nuevo rompe el servicio).
		if [ -f "$USER_HOME/birdnet-lsd/scripts/actualizar_birdnet_lsd.sh" ]; then
			bash "$USER_HOME/birdnet-lsd/scripts/actualizar_birdnet_lsd.sh"
		else
			# Arranque en frio: checkout viejo, todavia no tiene este script
			# (recien lo trae el pull). Sin chequeo de salud esta vez.
			git -C "$USER_HOME/birdnet-lsd" pull --quiet 2>/dev/null
			sudo systemctl restart birdnet-lsd.service 2>/dev/null
		fi
	else
		bash "$BASE_PATH/scripts/actualizar_modelo.sh"
		bash "$BASE_PATH/scripts/aplicar_ajuste_regional.sh"
	fi

	sudo nmcli radio wifi off
	sudo chown "$REAL_USER:$REAL_USER" "$USER_HOME/.config/rclone/rclone.conf"
fi

#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F'=' '/fin_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')
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
		find /home/lsd/BirdSongs/Extracted/By_Date/ -name "*.png" -delete
    	rm -rf /home/lsd/BirdSongs/Extracted/Charts/*
		HORA_INICIO=$(awk -F'=' '/inicio_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r' | tr -d ':')
        HORA_FIN=$(awk -F'=' '/fin_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r' | tr -d ':')
        DETECCIONES=$(find /home/lsd/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/ -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)
        python3 /home/lsd/log_sistema.py SIN_CONEXION atardecer $DETECCIONES
        bash /home/lsd/auto_sync_horarios.sh
        HORA_WAKE=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt | tr -d '\r')
        python3 /home/lsd/set_wake_pijuice.py $HORA_WAKE
        python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
"
		sudo poweroff
	fi

	sudo systemctl restart systemd-timesyncd
	sleep 5

	python3 /home/lsd/sync_pijuice_rtc.py

	find /home/lsd/BirdSongs/Extracted/By_Date/ -name "*.png" -delete

	rm -rf /home/lsd/BirdSongs/Extracted/Charts/*

	rclone copy /home/lsd/BirdSongs/Extracted/By_Date/ gdrive:Laboratorio\ 6/BirdNET_Detecciones --include "*.mp3"

	HORA_INICIO=$(awk -F'=' '/inicio_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r' | tr -d ':')
	HORA_FIN=$(awk -F'=' '/fin_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r' | tr -d ':')
	DETECCIONES=$(find /home/lsd/BirdSongs/Extracted/By_Date/$(date +%Y-%m-%d)/ -name "*.mp3" 2>/dev/null | grep -oP "birdnet-\K[0-9]{2}:[0-9]{2}" | awk -F: -v ini="$HORA_INICIO" -v fin="$HORA_FIN" '{t=$1*100+$2; if(t>=ini && t<=fin) print}' | wc -l)

	python3 /home/lsd/log_sistema.py FIN atardecer $DETECCIONES

	bash /home/lsd/auto_sync_horarios.sh

	rclone copy gdrive:Laboratorio\ 6/config_horarios.txt /home/lsd/

	rclone copy /home/lsd/log_sistema.txt gdrive:Laboratorio\ 6/

	sudo nmcli radio wifi off

	HORA_WAKE=$(awk -F' = ' '/inicio_amanecer/{print $2}' /home/lsd/config_horarios.txt | tr -d '\r')
	
	python3 /home/lsd/set_wake_pijuice.py $HORA_WAKE
	python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
pj.power.SetPowerOff(30)
	"
	sudo poweroff

	echo "Cierre atardecer completado a las $HORA_ACTUAL"
fi

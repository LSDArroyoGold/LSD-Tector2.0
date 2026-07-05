#!/bin/bash

export RCLONE_CONFIG=/home/lsd/.config/rclone/rclone.conf
export HOME=/home/lsd

HORARIO=$(awk -F' = ' '/inicio_atardecer/{print $2}' /home/lsd/config_horarios.txt |  tr -d '\r')
HORA_ACTUAL=$(date +%H:%M)

HORARIO_DELAY=$(echo "$HORARIO" | awk -F: '{m=$2+2; h=$1; if(m>=60){m=m-60} printf "%02d:%02d\n", h, m}')

if [ "$HORA_ACTUAL" = "$HORARIO_DELAY" ]; then

	UMBRAL=$(python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)

CONSUMO_W='$(awk -F'=' '/CONSUMO_W/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')'

AUTO_SYNC='$(awk -F'=' '/AUTO_SYNC/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')'
if AUTO_SYNC == 'ON':
	duracion_h = '$(awk -F' = ' '/duracion_atardecer_sync/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')'
else:
	from datetime import datetime
	t_inicio = datetime.strptime('$(awk -F' = ' '/inicio_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')', '%H:%M')
	t_fin = datetime.strptime('$(awk -F' = ' '/fin_atardecer/{print $2}' /home/lsd/config_horarios.txt | tr -d ' \r')', '%H:%M')
	duracion_h = (t_fin - t_inicio).seconds / 3600

CONSUMO_WH = float(CONSUMO_W) * duracion_h
CAPACIDAD_MAH = $(awk -F' = ' '/CAPACIDAD_MAH/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
VOLTAJE = $(awk -F' = ' '/VOLTAJE_BATERIA/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')
MARGEN = $(awk -F' = ' '/MARGEN_SEGURIDAD/{print $2}' /home/lsd/config_general.txt | tr -d ' \r')

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

		python3 /home/lsd/log_sistema.py CANCELADA atardecer
		sudo nmcli radio wifi on
		INTENTOS=0
		until ping -c 1 google.com &>/dev/null || [ $INTENTOS -ge 6 ]; do
			sleep 5
			INTENTOS=$((INTENTOS + 1))
		done

		if ping -c 1 google.com &>/dev/null; then
			rclone copy /home/lsd/log_sistema.txt gdrive:Laboratorio\ 6/
		fi

		sudo nmcli radio wifi off

		sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf

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
	else
		python3 /home/lsd/log_sistema.py INICIO atardecer
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
		rclone copy /home/lsd/log_sistema.txt gdrive:Laboratorio\ 6/
		sudo nmcli radio wifi off

		sudo chown lsd:lsd /home/lsd/.config/rclone/rclone.conf
	fi
fi

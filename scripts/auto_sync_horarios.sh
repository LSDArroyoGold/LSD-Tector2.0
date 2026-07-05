#!/bin/bash

AUTO_SYNC=$(awk -F'=' '/AUTO_SYNC/{print $2}' /home/lsd/config_horarios.txt | tr -d "\r")

if [ "$AUTO_SYNC" = "ON" ]; then
	python3 /home/lsd/calcular_horarios.py
fi

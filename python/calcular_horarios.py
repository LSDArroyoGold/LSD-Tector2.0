from astral import LocationInfo
from astral.sun import sun
from datetime import date, timedelta
import subprocess

# Leer coordenadas desde config_general.txt
def leer_config(archivo, clave):
    with open(archivo) as f:
        for linea in f:
            if clave + '=' in linea:
                return linea.split('=',1)[1].strip()

LAT = float(leer_config('/home/lsd/config_general.txt', 'LAT'))
LON = float(leer_config('/home/lsd/config_general.txt', 'LON'))

DURACION_AMANECER = float(leer_config('/home/lsd/config_horarios.txt', 'duracion_amanecer_sync'))
DURACION_ATARDECER = float(leer_config('/home/lsd/config_horarios.txt', 'duracion_atardecer_sync'))

OFFSET_AMANECER = float(leer_config('/home/lsd/config_horarios.txt', 'offset_amanecer_sync'))
OFFSET_ATARDECER = float(leer_config('/home/lsd/config_horarios.txt', 'offset_atardecer_sync'))

# Calcular horarios de hoy y mañana
ubicacion = LocationInfo(latitude=LAT, longitude=LON)
hoy = sun(ubicacion.observer, date=date.today())
manana = sun(ubicacion.observer, date=date.today() + timedelta(days=1))

#Le resto 3 por el huso horario de Argentina

inicio_atardecer = (hoy['sunset'] - timedelta(hours=3) + timedelta(minutes=OFFSET_ATARDECER)).strftime('%H:%M')
fin_atardecer = (hoy['sunset'] - timedelta(hours=3) + timedelta(hours=DURACION_ATARDECER) + timedelta(minutes=OFFSET_ATARDECER)).strftime('%H:%M')
inicio_amanecer = (manana['sunrise'] - timedelta(hours=3) + timedelta(minutes=OFFSET_AMANECER)).strftime('%H:%M')
fin_amanecer = (manana['sunrise'] - timedelta(hours=3) + timedelta(hours=DURACION_AMANECER) + timedelta(minutes=OFFSET_AMANECER)).strftime('%H:%M')

print(f"inicio_atardecer = {inicio_atardecer}")
print(f"fin_atardecer = {fin_atardecer}")
print(f"inicio_amanecer = {inicio_amanecer}")
print(f"fin_amanecer = {fin_amanecer}")

import re

with open('/home/lsd/config_horarios.txt','r') as f:
	contenido = f.read()

contenido = re.sub(r'inicio_amanecer = .*', f'inicio_amanecer = {inicio_amanecer}', contenido)
contenido = re.sub(r'fin_amanecer = .*', f'fin_amanecer = {fin_amanecer}', contenido)
contenido = re.sub(r'inicio_atardecer = .*', f'inicio_atardecer = {inicio_atardecer}', contenido)
contenido = re.sub(r'fin_atardecer = .*', f'fin_atardecer = {fin_atardecer}', contenido)

with open('/home/lsd/config_horarios.txt','w') as f:
	f.write(contenido)

import subprocess
subprocess.run(['rclone', 'copy', '/home/lsd/config_horarios.txt', 'gdrive:Laboratorio 6/'])

print("config_horarios.txt actualizado y subido a Drive")

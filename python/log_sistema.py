import sys
from pathlib import Path
from datetime import datetime

BASE_PATH = Path(__file__).resolve().parent.parent
LOG_SISTEMA = BASE_PATH / 'log_sistema.txt'

timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')
evento = sys.argv[1]

# Mensaje libre: no requiere lectura de batería
if evento == 'MSG':
	mensaje = sys.argv[2]
	linea = f"[{timestamp}] {mensaje}\n"
else:
	# Eventos de ventana: requieren nivel de batería del PiJuice
	sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
	from pijuice import PiJuice
	pj = PiJuice(1, 0x14)
	nivel = pj.status.GetChargeLevel()['data']
	ventana = sys.argv[2]

	if evento == 'FIN':
		detecciones = sys.argv[3] if len(sys.argv) > 3 else '0'
		linea = f"[{timestamp}] FIN ventana {ventana} | Batería: {nivel}% | Detecciones subidas: {detecciones}\n"
	elif evento == 'CANCELADA':
		linea = f"[{timestamp}] VENTANA cancelada - {ventana} | Batería: {nivel}%\n"
	elif evento == 'SIN_CONEXION':
		detecciones = sys.argv[3] if len(sys.argv) > 3 else '0'
		linea = f"[{timestamp}] FIN ventana {ventana} | SIN CONEXIÓN, archivos se subirán en la próxima ventana | Batería: {nivel}% | Detecciones: {detecciones}\n"
	else:
		linea = f"[{timestamp}] INICIO ventana {ventana} | Batería: {nivel}%\n"

with open(LOG_SISTEMA,'a') as f:
	f.write(linea)
print(linea.strip())

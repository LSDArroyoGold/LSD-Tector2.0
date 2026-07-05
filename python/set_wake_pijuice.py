import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice

pj = PiJuice(1, 0x14)
hora_wake = sys.argv[1]
h, m = map(int, hora_wake.split(':'))

pj.rtcAlarm.SetAlarm({
	'second':0,
	'minute': m,
	'hour': h,
	'day': 'EVERY_DAY'
})
pj.rtcAlarm.SetWakeupEnabled(True)

print(f"Alarma programada para las {hora_wake}")
print(pj.rtcAlarm.GetAlarm())

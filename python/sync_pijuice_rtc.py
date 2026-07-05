import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
from datetime import datetime

pj = PiJuice(1, 0x14)
now = datetime.now()

pj.rtcAlarm.SetTime({
	'second': now.second,
	'minute': now.minute,
	'hour': now.hour,
	'day': now.day,
	'month': now.month,
	'year': now.year,
	'weekday': now.weekday() + 1,
	'subsecond' : 0
})
print("RTC PiJuice sincronizado a las", now.strftime('%H:%M'))


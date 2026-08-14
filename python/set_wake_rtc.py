import sys

# Reemplaza a set_wake_pijuice.py de la v1.1. Ahí, pj.rtcAlarm.SetAlarm()
# programaba la alarma en el RTC propio de la PiJuice, y pj.power.SetPowerOff()
# le ordenaba a su microcontrolador cortar la alimentación de la Raspberry
# X segundos después del apagado del SO — el corte físico real quedaba
# resuelto enteramente por la PiJuice.
#
# Sin PiJuice, la Raspberry NO se apaga entre ventanas todavía: no hay
# circuito de corte de energía armado (ver discusión del 14/8 sobre el
# DS3231 + latch + MOSFET). Por ahora esta rutina es un no-op: no arma
# ninguna alarma porque no hay nada que la vaya a escuchar mientras el
# equipo esté siempre encendido.

hora_wake = sys.argv[1] if len(sys.argv) > 1 else None
print(f"(sin efecto: todavía no hay circuito de corte de energía) "
      f"próxima ventana calculada para las {hora_wake}, la Pi sigue encendida")

# ============================================================================
# PENDIENTE — retomar cuando el circuito DS3231 + latch + MOSFET esté armado.
#
# El DS3231, configurado como RTC del kernel (dtoverlay=i2c-rtc,ds3231,
# aparece como /dev/rtc0), expone su alarma nativa a través de
# /sys/class/rtc/rtc0/wakealarm: escribir ahí un timestamp Unix programa el
# registro de alarma del propio chip, que es lo que hace bajar su pin
# SQW/INT a la hora indicada — la señal que en el hardware nuevo dispara el
# latch que enciende la Pi (ver Sección 3.5 del manual de la v1.0 para el
# circuito original del botón, que el nuevo latch reutiliza en parte).
#
# import subprocess
# from datetime import datetime
#
# hora_wake = sys.argv[1]  # formato HH:MM
# h, m = map(int, hora_wake.split(':'))
#
# ahora = datetime.now()
# objetivo = ahora.replace(hour=h, minute=m, second=0, microsecond=0)
# if objetivo <= ahora:
#     from datetime import timedelta
#     objetivo += timedelta(days=1)
#
# timestamp = int(objetivo.timestamp())
#
# # Limpiar cualquier alarma previa antes de programar la nueva
# subprocess.run(['sudo', 'sh', '-c', 'echo 0 > /sys/class/rtc/rtc0/wakealarm'])
# subprocess.run(['sudo', 'sh', '-c', f'echo {timestamp} > /sys/class/rtc/rtc0/wakealarm'])
#
# print(f"Alarma DS3231 programada para las {hora_wake} ({timestamp})")
#
# # El corte real de alimentación (equivalente a pj.power.SetPowerOff(30) de
# # la v1.1) lo va a dar el circuito de latch + MOSFET, no software — ver
# # notas del README sobre el rediseño del circuito de botón/RTC.
# ============================================================================

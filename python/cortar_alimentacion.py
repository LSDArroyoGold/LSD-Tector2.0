import subprocess
import time

import RPi.GPIO as GPIO

# Corta la alimentacion de la Raspberry pulsando a bajo el pin que maneja
# /CLR1 del latch (74HC74 + MOSFET P, ver tabla de pines del circuito -- R2
# lo mantiene alto en reposo, este pulso lo lleva a GND un instante). Eso
# fuerza el RESET del latch, que corta el MOSFET y saca los 5V que
# alimentan a la Pi entera -- incluida esta misma linea de GPIO.
#
# Se invoca automaticamente via cortar-alimentacion.service (ExecStop=, ver
# ese archivo) justo antes del apagado final del kernel, cuando systemd ya
# termino de sincronizar y desmontar todo -- no a mano desde los scripts de
# cierre. Asi el corte de energia solo pasa despues de un apagado limpio de
# verdad, nunca a mitad de un flush a disco.

PIN_CLR1 = 6  # BCM -- /CLR1 del 74HC74, ver tabla de pines del circuito
DURACION_PULSO_S = 0.3  # el 74HC74 necesita nanosegundos, esto sobra por lejos

GPIO.setmode(GPIO.BCM)
GPIO.setwarnings(False)
GPIO.setup(PIN_CLR1, GPIO.OUT, initial=GPIO.HIGH)

subprocess.run(
    ["logger", "-t", "cortar-alimentacion", "pulsando GPIO6 para cortar alimentacion"]
)

GPIO.output(PIN_CLR1, GPIO.LOW)
time.sleep(DURACION_PULSO_S)

# Si todo salio bien, la alimentacion ya se cortó y este proceso se
# interrumpe antes de llegar aca. Si llegamos hasta este punto (banco de
# pruebas sin la placa conectada, corte que no ocurrio, etc.) devolvemos
# GPIO6 a alto para no dejar la linea forzada a GND de forma permanente.
GPIO.output(PIN_CLR1, GPIO.HIGH)
GPIO.cleanup()

subprocess.run(
    ["logger", "-t", "cortar-alimentacion",
     "el pulso termino y la Pi sigue con energia -- el corte no se disparo"]
)

# Lectura directa del INA219 por I2C (sin la libreria pi-ina219 -- esa
# depende de Adafruit_GPIO, que falla al arrancar en la Pi 4 con kernels
# nuevos: "RuntimeError: Could not determine default I2C bus for platform"
# porque su deteccion de hardware esta desactualizada. Confirmado el
# 3/9/2026 en tector2. Esto de aca es mas simple igual: el protocolo del
# INA219 son 4 registros de 16 bits, no hace falta una libreria para eso.
#
# PENDIENTE: esto es el driver de lectura, verificado funcionando en banco
# (7.596V / 478mA con la Pi corriendo birdnet-lsd normalmente, valores con
# sentido fisico para el pack 2S2P Samsung INR18650-35E). Todavia NO esta
# integrado a ningun watchdog ni cron -- ver la nota completa en
# config/config_general.txt (seccion INA219) para el diseño acordado
# (corte de seguridad por umbral simple + % estimado compensado por IR
# con curva propia via calibracion) antes de escribir ese watchdog.

import smbus2
import time

ADDR = 0x40  # direccion I2C default del INA219 (el DS3231 esta en 0x68,
             # mismo bus 1, sin conflicto)
BUS_NUM = 1

# Calibracion estandar del datasheet para shunt=0.1ohm (el valor tipico de
# estos modulos -- confirmar contra la placa propia si difiere), rango
# maximo ~3.2A: current_LSB = 100uA,
# cal = trunc(0.04096 / (100e-6 * 0.1)) = 4096
CAL = 4096
CURRENT_LSB_MA = 0.1  # mA por cuenta, con la calibracion de arriba

# Config register: 0x399F = rango 16V, ganancia shunt /8 (320mV), ADC de
# 12 bits, conversion continua de bus+shunt. Valor estandar del datasheet.
CONFIG_VALUE = 0x399F


def leer(bus_num=BUS_NUM, addr=ADDR):
    """Devuelve (voltaje_V, corriente_mA). Configura y calibra en cada
    llamada -- son 2 escrituras I2C, no vale la pena optimizar dado que
    esto se va a llamar cada varios minutos, no en un loop ajustado."""
    bus = smbus2.SMBus(bus_num)
    try:
        bus.write_i2c_block_data(addr, 0x00, [CONFIG_VALUE >> 8, CONFIG_VALUE & 0xFF])
        bus.write_i2c_block_data(addr, 0x05, [(CAL >> 8) & 0xFF, CAL & 0xFF])
        time.sleep(0.05)  # tiempo de conversion del ADC

        raw_v = bus.read_i2c_block_data(addr, 0x02, 2)
        v_val = (raw_v[0] << 8) | raw_v[1]
        if v_val & 0x1:
            raise RuntimeError("INA219: overflow en la medicion de bus voltage")
        voltaje_v = ((v_val >> 3) * 4) / 1000

        raw_i = bus.read_i2c_block_data(addr, 0x04, 2)
        i_val = (raw_i[0] << 8) | raw_i[1]
        if i_val > 32767:
            i_val -= 65536
        corriente_ma = i_val * CURRENT_LSB_MA

        return voltaje_v, corriente_ma
    finally:
        bus.close()


if __name__ == "__main__":
    v, i = leer()
    print(f"Voltaje (pack): {v:.3f} V")
    print(f"Corriente: {i:.1f} mA")

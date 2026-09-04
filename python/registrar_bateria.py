#!/usr/bin/env python3
# registrar_bateria.py - lectura DUAL del INA219 para el watchdog de
# bateria (chequeo_bateria.sh): una CON el MPPT conectado tal cual esta
# (para ver el efecto real de la carga) y otra SIN carga (aislada, via el
# aislador de carga MPPT -- descarga pura). Loguea las dos a
# log_bateria.txt para caracterizar ambos regimenes con el tiempo, y
# reporta por stdout la lectura SIN CARGA en el mismo formato que
# leer_ina219.py -- es la UNICA que participa de la decision de seguridad
# del watchdog (nunca la que tiene el MPPT metiendo carga, ver la
# justificacion completa en config/config_general.txt).

import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leer_ina219

ARCHIVO_LOG = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "log_bateria.txt"
)


def fmt(x, decimales):
    return f"{x:.{decimales}f}" if x is not None else ""


def main():
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")

    try:
        v_con, i_con = leer_ina219.leer(aislar_carga=False)
    except Exception as e:
        v_con, i_con = None, None
        print(f"ALERTA registrar_bateria: fallo lectura CON carga -- {e}", file=sys.stderr)

    try:
        v_sin, i_sin = leer_ina219.leer(aislar_carga=True)
    except Exception as e:
        v_sin, i_sin = None, None
        print(f"ALERTA registrar_bateria: fallo lectura SIN carga -- {e}", file=sys.stderr)

    existe = os.path.exists(ARCHIVO_LOG)
    with open(ARCHIVO_LOG, "a") as f:
        if not existe:
            f.write(
                "timestamp,voltaje_con_carga_v,corriente_con_carga_ma,"
                "voltaje_sin_carga_v,corriente_sin_carga_ma\n"
            )
        f.write(
            f"{timestamp},{fmt(v_con, 3)},{fmt(i_con, 1)},"
            f"{fmt(v_sin, 3)},{fmt(i_sin, 1)}\n"
        )

    # chequeo_bateria.sh sigue parseando exactamente este formato -- la
    # decision de corte se toma SOLO con la lectura SIN CARGA.
    if v_sin is not None:
        print(f"Voltaje (pack): {v_sin:.3f} V")
        print(f"Corriente: {i_sin:.1f} mA")
    else:
        print("ERROR: no se pudo leer el INA219 en regimen SIN carga (ver stderr)")
        sys.exit(1)


if __name__ == "__main__":
    main()

#!/bin/bash
#
# install.sh - Instalador del LSD-Tector 2.0
#
# Configura crontab, servicios systemd y permisos, autodetectando la
# ubicacion del repositorio. No instala BirdNET-Pi, rclone ni dependencias
# del sistema: esos pasos son manuales y estan documentados en el README.
#
# Uso: ./install.sh   (NO con sudo; el script pide sudo donde lo necesita)

set -e

# --- Autodeteccion de rutas ---
BASE_PATH="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SCRIPTS_DIR="$BASE_PATH/scripts"
PYTHON_DIR="$BASE_PATH/python"
SYSTEMD_DIR="$BASE_PATH/systemd"

# --- Deteccion del usuario real (aunque se corra con sudo por error) ---
REAL_USER="${SUDO_USER:-$(whoami)}"

echo "==> Instalando LSD-Tector 2.0"
echo "    Repositorio detectado en: $BASE_PATH"
echo "    Usuario: $REAL_USER"
echo ""

# --- 1. Permisos de ejecucion a los scripts ---
echo "==> Dando permisos de ejecucion a los scripts .sh"
chmod +x "$SCRIPTS_DIR"/*.sh

# --- 2. Servicios systemd ---
echo "==> Instalando servicios systemd"

# hotspot.service: reemplazar el placeholder __BASE_PATH__ por la ruta real
sed "s|__BASE_PATH__|$BASE_PATH|g" "$SYSTEMD_DIR/hotspot.service" \
    | sudo tee /etc/systemd/system/hotspot.service > /dev/null

# sync-rtc.service: no tiene rutas del proyecto, se copia tal cual
sudo cp "$SYSTEMD_DIR/sync-rtc.service" /etc/systemd/system/sync-rtc.service

sudo chmod 644 /etc/systemd/system/hotspot.service
sudo chmod 644 /etc/systemd/system/sync-rtc.service

sudo systemctl daemon-reload
sudo systemctl enable hotspot.service
sudo systemctl enable sync-rtc.service

echo "    Servicios hotspot.service y sync-rtc.service habilitados"

# --- 3. Crontab del usuario ---
echo "==> Configurando crontab para el usuario $REAL_USER"

# Lineas del crontab, apuntando a las rutas reales del repo
CRON_LINES="* * * * * $SCRIPTS_DIR/cierre_amanecer.sh
* * * * * $SCRIPTS_DIR/cierre_atardecer.sh
* * * * * $SCRIPTS_DIR/inicio_amanecer.sh
* * * * * $SCRIPTS_DIR/inicio_atardecer.sh
* * * * * python3 $PYTHON_DIR/check_button.py"

# Tomar el crontab actual del usuario (si existe), quitar cualquier linea previa
# de LSD-Tector para no duplicar, y agregar las nuevas.
CRON_ACTUAL=$(crontab -u "$REAL_USER" -l 2>/dev/null | grep -v "$SCRIPTS_DIR" | grep -v "$PYTHON_DIR/check_button.py" || true)

printf '%s\n%s\n' "$CRON_ACTUAL" "$CRON_LINES" | grep -v '^$' | crontab -u "$REAL_USER" -

echo "    Crontab configurado con 5 tareas"

# --- Fin ---
echo ""
echo "==> Instalacion completada."
echo "    Verifica los servicios con: sudo systemctl status hotspot.service"
echo "    Verifica el crontab con:    crontab -l"

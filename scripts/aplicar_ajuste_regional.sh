#!/bin/bash
#
# aplicar_ajuste_regional.sh - Ajusta el clasificador reentrenado segun la
# frecuencia real de observacion de cada una de las 193 especies locales
# en la region donde esta desplegado el dispositivo, para que especies
# localmente comunes le ganen mas facil a especies localmente raras
# cuando el sonido es ambiguo. Nunca descarta ninguna especie por
# completo, solo reordena el margen de confianza.
#
# Importante: este script NUNCA se conecta a eBird. Los datos de
# frecuencia por region se bajan a mano UNA VEZ por el equipo (desde una
# cuenta de eBird propia) y se versionan en el repo
# LSDTector-BirdNET-retrain-bsas, bajo frecuencias/<region>.txt. El
# dispositivo en el campo solo lee el archivo que ya viene con el repo
# (via raw.githubusercontent.com, igual que el resto del modelo) si existe
# para su region -- no hay llamados en vivo a eBird desde ningun
# dispositivo, a proposito, para no atar el producto a los terminos de
# uso de esa API (ver README de LSDTector-BirdNET-retrain-bsas).
#
# Corre DESPUES de actualizar_modelo.sh (necesita que el modelo universal
# ya este instalado) y es enteramente opcional y silencioso: si todavia
# no existe un archivo de frecuencias para la region del dispositivo, o
# falta el entorno ~/birdnet-v2-env, no hace nada y el dispositivo sigue
# con el modelo universal sin ajustar -- ni error ni bloqueo.
#
# Requisitos para que se active (se chequean en orden, si falta alguno se
# sale sin tocar nada):
#   1. BirdNET-Pi instalado.
#   2. LAT/LON ya geolocalizadas (se completan solas en el primer
#      arranque via hotspot.sh).
#   3. El entorno ~/birdnet-v2-env instalado (bash instalar.sh dentro de
#      un clon de LSDTector-BirdNET-retrain-bsas -- ver su README).
#   4. Que exista frecuencias/<region-detectada>.txt en el repo del
#      modelo para la region de este dispositivo (el propio script de
#      Python hace el reverse geocoding y busca el archivo; si no existe
#      todavia para esa region, termina con exit code 2, no es un error).
#
# Solo hace trabajo real (que tarda, involucra TensorFlow) cuando algo
# relevante cambio: el modelo universal se actualizo, o la ubicacion
# cambio. En cualquier otra corrida sale de inmediato.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REAL_USER="${SUDO_USER:-$(whoami)}"
USER_HOME="$(getent passwd "$REAL_USER" | cut -d: -f6)"

BIRDNET_PI_DIR="$USER_HOME/BirdNET-Pi"
BIRDNET_MODEL_DIR="$BIRDNET_PI_DIR/model"
CONFIG_PATH="$BASE_PATH/config/config_general.txt"
VENV_PYTHON="$USER_HOME/birdnet-v2-env/bin/python3"

log() {
	python3 "$BASE_PATH/python/log_sistema.py" MSG "$1"
}

if [ ! -d "$BIRDNET_MODEL_DIR" ]; then
	exit 0  # BirdNET-Pi no instalado, nada que hacer.
fi

LAT=$(awk -F'=' '/^LAT=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
LON=$(awk -F'=' '/^LON=/{print $2}' "$CONFIG_PATH" | tr -d '\r')
if [ -z "$LAT" ] || [ -z "$LON" ]; then
	exit 0  # Todavia sin geolocalizar (antes del primer arranque exitoso).
fi

if [ ! -x "$VENV_PYTHON" ]; then
	exit 0  # Falta el entorno de LSDTector-BirdNET-retrain-bsas/instalar.sh. Feature opcional, sin avisar cada vez.
fi

REPO="LSDArroyoGold/LSDTector-BirdNET-retrain-bsas"
RAW="https://raw.githubusercontent.com/$REPO/main"

MARCA_MODELO="$BASE_PATH/.ultima_actualizacion_modelo"
MARCA_REGIONAL="$BASE_PATH/.ultimo_ajuste_regional"

SHA_MODELO=$(cat "$MARCA_MODELO" 2>/dev/null)
ESTADO_ACTUAL="${SHA_MODELO}|${LAT}|${LON}"
ESTADO_PREVIO=$(cat "$MARCA_REGIONAL" 2>/dev/null)

if [ "$ESTADO_ACTUAL" = "$ESTADO_PREVIO" ]; then
	exit 0  # Ni el modelo base ni la ubicacion cambiaron desde el ultimo intento.
fi

TMP="$BASE_PATH/.ajuste_regional_tmp"
rm -rf "$TMP"
mkdir -p "$TMP/modelo"

if ! curl -sf -o "$TMP/generar_modelo_regional.py" "$RAW/generar_modelo_regional.py"; then
	echo "Fallo la descarga de generar_modelo_regional.py, se reintenta en la proxima ventana" >&2
	rm -rf "$TMP"
	exit 1
fi

if ! curl -sf -o "$TMP/modelo/pesos_193_locales.npz" "$RAW/modelo/pesos_193_locales.npz"; then
	echo "Fallo la descarga de pesos_193_locales.npz, se reintenta en la proxima ventana" >&2
	rm -rf "$TMP"
	exit 1
fi

# El script de Python hace el reverse geocoding el mismo y busca el
# archivo de frecuencias correspondiente via raw.githubusercontent.com
# (parametro --frecuencias-base-url) -- asi no hace falta bajar a mano
# los ~200 archivos de region posibles, solo el que corresponda.
if ! "$VENV_PYTHON" "$TMP/generar_modelo_regional.py" \
	--lat "$LAT" --lon "$LON" \
	--pesos "$TMP/modelo/pesos_193_locales.npz" \
	--frecuencias-raw-base "$RAW/frecuencias" \
	--out-dir "$TMP/salida" --out-nombre "regional" > "$TMP/log.txt" 2>&1; then

	if grep -q "No hay archivo de frecuencias" "$TMP/log.txt" 2>/dev/null; then
		# No es un error: todavia no se cargo el archivo de esta region.
		echo "$ESTADO_ACTUAL" > "$MARCA_REGIONAL"  # no reintentar hasta que algo cambie
		rm -rf "$TMP"
		exit 0
	fi

	echo "Fallo la generacion del modelo regional, sigue el modelo universal. Detalle en $TMP/log.txt" >&2
	cat "$TMP/log.txt" >&2
	rm -rf "$TMP"
	exit 1
fi

TFLITE_GENERADO="$TMP/salida/regional.tflite"
LABELS_GENERADO="$TMP/salida/regional_Labels.txt"
if [ ! -s "$TFLITE_GENERADO" ] || [ ! -s "$LABELS_GENERADO" ]; then
	echo "El script regional no genero los archivos esperados, aborto sin tocar el modelo actual" >&2
	rm -rf "$TMP"
	exit 1
fi

DESTINO_TFLITE="$BIRDNET_MODEL_DIR/BirdNET_GLOBAL_6K_V2.4_Model_FP16.tflite"
DESTINO_LABELS="$BIRDNET_MODEL_DIR/BirdNET_GLOBAL_6K_V2.4_Model_FP16_Labels.txt"

# Mismo filesystem que BIRDNET_MODEL_DIR: mv es atomico.
mv "$TFLITE_GENERADO" "$DESTINO_TFLITE"
mv "$LABELS_GENERADO" "$DESTINO_LABELS"

REGION=$(python3 -c "
import json
try:
    with open('$TMP/salida/ajuste_regional_meta.json', encoding='utf-8') as f:
        print(json.load(f).get('region_code', '?'))
except Exception:
    print('?')
")

sudo systemctl restart birdnet_analysis.service

echo "$ESTADO_ACTUAL" > "$MARCA_REGIONAL"
rm -rf "$TMP"

log "Modelo ajustado a la region $REGION (frecuencias reales de las 193 especies locales)."

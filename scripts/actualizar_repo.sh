#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
BASE_PATH="$(dirname "$SCRIPT_DIR")"

REPO="LSDArroyoGold/LSD-Tector2.0"
RAW="https://raw.githubusercontent.com/$REPO/main"
API="https://api.github.com/repos/$REPO/commits/main"
MARCA="$BASE_PATH/.ultima_actualizacion"
TMP="$BASE_PATH/.actualizar_tmp"

ULTIMO_SHA=$(cat "$MARCA" 2>/dev/null)

SHA_ACTUAL=$(curl -s "$API" | python3 -c "import sys,json; print(json.load(sys.stdin)['sha'])" 2>/dev/null)

if [ -z "$SHA_ACTUAL" ] || [ "$SHA_ACTUAL" = "$ULTIMO_SHA" ]; then
	exit 0
fi

# Todos los archivos que corren activamente. config/ queda afuera a
# propósito: config_general.txt y config_horarios.txt guardan estado en
# vivo del dispositivo (FIRST_START, coordenadas reales, horarios
# recalculados), no solo configuración de fábrica.
ARCHIVOS="scripts/inicio_amanecer.sh scripts/inicio_atardecer.sh scripts/cierre_amanecer.sh scripts/cierre_atardecer.sh scripts/hotspot.sh scripts/auto_sync_horarios.sh scripts/generar_log_reciente.sh scripts/actualizar_repo.sh scripts/actualizar_modelo.sh scripts/aplicar_ajuste_regional.sh python/calcular_horarios.py python/check_button.py python/log_sistema.py python/portal_configuracion.py python/set_wake_rtc.py python/sync_rtc.py systemd/hotspot.service systemd/sync-rtc.service"

rm -rf "$TMP"
mkdir -p "$TMP"

for ARCHIVO in $ARCHIVOS; do
	mkdir -p "$TMP/$(dirname "$ARCHIVO")"
	if ! curl -sf -o "$TMP/$ARCHIVO" "$RAW/$ARCHIVO"; then
		echo "Fallo la descarga de $ARCHIVO, aborto sin tocar nada" >&2
		rm -rf "$TMP"
		exit 1
	fi
done

SELF_CAMBIO=0
if [ ! -f "$BASE_PATH/scripts/actualizar_repo.sh" ] || ! cmp -s "$TMP/scripts/actualizar_repo.sh" "$BASE_PATH/scripts/actualizar_repo.sh"; then
	SELF_CAMBIO=1
fi

# Mismo filesystem que BASE_PATH: el mv es un rename atómico, seguro
# incluso si el archivo que se reemplaza es el que está corriendo ahora
# mismo (este mismo script, o el inicio_*.sh que lo llamó).
for ARCHIVO in $ARCHIVOS; do
	case "$ARCHIVO" in
		systemd/hotspot.service)
			# Tiene el placeholder __BASE_PATH__ (ver install.sh) -- no se
			# puede copiar tal cual a /etc/systemd/system.
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			sed "s|__BASE_PATH__|$BASE_PATH|g" "$BASE_PATH/$ARCHIVO" | sudo tee /etc/systemd/system/hotspot.service > /dev/null
			sudo chmod 644 /etc/systemd/system/hotspot.service
			;;
		systemd/*)
			NOMBRE=$(basename "$ARCHIVO")
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			sudo cp "$BASE_PATH/$ARCHIVO" "/etc/systemd/system/$NOMBRE"
			sudo chmod 644 "/etc/systemd/system/$NOMBRE"
			;;
		*)
			mv "$TMP/$ARCHIVO" "$BASE_PATH/$ARCHIVO"
			;;
	esac
done

chmod +x "$BASE_PATH"/scripts/*.sh
sudo systemctl daemon-reload

rm -rf "$TMP"

# Si actualizar_repo.sh cambió, la lista de $ARCHIVOS que acabamos de usar
# para bajar todo puede ser la vieja (la que ya estaba cargada en memoria
# al arrancar esta corrida) -- por ejemplo, si el mismo commit que nos trajo
# esta versión nueva también agregó un archivo a la lista. Nos volvemos a
# ejecutar una vez con la versión ya instalada para completar el ciclo con
# la lista correcta antes de marcar la actualización como terminada.
# _REEXEC evita un bucle si por lo que sea el archivo siguiera "cambiando".
if [ "$SELF_CAMBIO" = "1" ] && [ -z "$_REEXEC" ]; then
	_REEXEC=1 exec bash "$BASE_PATH/scripts/actualizar_repo.sh"
fi

echo "$SHA_ACTUAL" > "$MARCA"

echo "[$(date '+%Y-%m-%d %H:%M')] Software actualizado ($SHA_ACTUAL)" >> "$BASE_PATH/log_sistema.txt"

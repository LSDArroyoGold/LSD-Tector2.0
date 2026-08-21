# LSD-Tector 2.0 — Software

Este repositorio contiene todo el software necesario para replicar el sistema de monitoreo autónomo de aves LSD-Tector, desarrollado en el Laboratorio de Sistemas Dinámicos (LSD), Facultad de Ciencias Exactas y Naturales, Universidad de Buenos Aires.

El sistema gestiona automáticamente ventanas de grabación en horarios de amanecer y atardecer, identifica especies mediante BirdNET-Pi, y envía detecciones a Google Drive. Para una descripción completa del hardware y el diseño físico del dispositivo, referirse al artículo asociado.

Este software fue desarrollado y probado sobre una **Raspberry Pi 4 Model B (2GB RAM)**. No se garantiza compatibilidad con otros modelos o configuraciones de hardware.

> [!IMPORTANT]
> **Hardware en transición respecto al LSD-Tector 1.0/1.1.** Esta versión reemplaza la PiJuice HAT por un RTC externo **DS3231** (batería de dos celdas, gestión de energía a definir) y, más adelante, un módulo **INA219** para medir batería por voltaje/corriente. Al día de hoy:
> - **No hay monitoreo de batería.** El código que lo hacía (watchdog o umbral predictivo) está comentado en `inicio_*.sh`, `cierre_*.sh` y `log_sistema.py`, con una nota `PENDIENTE` explicando qué retomar cuando el INA219 esté instalado. El umbral de corte ya está definido — `UMBRAL_BATERIA_V=6.9` (pack 2S, ≈3.45V/celda, ≈15% de capacidad) — comentado en `config/config_general.txt` junto con su justificación; solo falta el hardware para aplicarlo.
> - **La Raspberry no se apaga entre ventanas todavía.** Falta el circuito que corte y reponga físicamente la alimentación a partir de la alarma del DS3231 (un MOSFET/latch disparado por su pin SQW/INT, con un temporizador de gracia para el apagado prolijo — ver la discusión de diseño del 14/8 en el cuaderno de laboratorio). Hasta que ese circuito exista, el equipo queda siempre encendido y `set_wake_rtc.py` no tiene efecto real; la implementación completa está comentada ahí mismo, lista para descomentar.
>
> Ninguna de estas ausencias impide poner en marcha el dispositivo: las ventanas de grabación arrancan y cierran igual, solo que sin corte de energía ni chequeo de batería.

---

## Dependencias

- Raspberry Pi OS Lite 64-bit (Bookworm)
- BirdNET-Pi (ver paso 9; salteable si por ahora solo se quiere probar el software propio del LSD-Tector)
- [LSDTector-BirdNET-retrain-bsas](https://github.com/LSDArroyoGold/LSDTector-BirdNET-retrain-bsas) (clasificador reentrenado, opcional — ver paso 9.5)
- Python 3 (incluido en Raspberry Pi OS)
- rclone
- astral (librería Python) — instalada automáticamente por `install.sh`
- nmcli (incluido en Raspberry Pi OS)
- dnsmasq y util-linux-extra — instalados automáticamente por `install.sh`
- DS3231 (RTC externo, soportado nativamente por el kernel de Linux — no requiere ninguna librería propia)

### 1. Sistema operativo

Instalar **Raspberry Pi OS Lite 64-bit (Bookworm)** en la microSD usando [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Durante el proceso de flasheo, en la sección de configuración avanzada del Imager (ícono del engranaje), crear un usuario con nombre y contraseña a elección, y habilitar SSH.

> [!NOTE]
> Se usa Lite y no Full: el dispositivo corre siempre headless (todo el manejo es por SSH/cron), y el entorno gráfico de Full no aporta nada salvo consumo de batería — en la v1.1 medimos ~19% de reducción real al sacarlo de encendido permanente. Arrancar directo con Lite evita ese ajuste manual.

> [!NOTE]
> Los scripts detectan automáticamente la ubicación del repositorio y el usuario del sistema, por lo que no es necesario usar un nombre de usuario específico ni una ruta fija. El repositorio puede clonarse en cualquier ubicación y con cualquier usuario.

Una vez flasheada la microSD, insertarla en la Raspberry Pi y encenderla.

### 2. Clonar el repositorio

Clonar este repositorio en la Raspberry Pi, en la ubicación deseada (por ejemplo, el directorio home del usuario):

```bash
cd ~
git clone https://github.com/LSDArroyoGold/LSD-Tector2.0.git
```

Los scripts se ejecutan directamente desde el repositorio, respetando su estructura de carpetas (`scripts/`, `python/`, `config/`, `systemd/`). No es necesario copiar ni mover archivos.

### 3. sudo sin contraseña

> [!IMPORTANT]
> Este paso no es opcional. Todo el sistema depende de que `cron` pueda ejecutar `sudo` (nmcli, systemctl, etc. en `inicio_*.sh`, `cierre_*.sh`, `hotspot.sh`) sin que haya nadie conectado para tipear una contraseña — el dispositivo corre desatendido en campo. También lo exige el instalador oficial de BirdNET-Pi (paso 9), que aborta si no lo detecta.

```bash
echo "$(whoami) ALL=(ALL) NOPASSWD: ALL" | sudo EDITOR="tee" visudo -f /etc/sudoers.d/010-lsd-nopasswd
sudo chmod 440 /etc/sudoers.d/010-lsd-nopasswd
sudo visudo -c
```

La tercera línea valida la sintaxis del archivo nuevo antes de confiar en él (evita dejar `sudo` roto por un error de tipeo). Verificar que funcionó:

```bash
sudo -n true && echo OK
```

### 4. Ejecutar el instalador

El script `install.sh` deja el sistema listo en una sola corrida: paquetes del sistema (`dnsmasq`, `util-linux-extra`), habilita I2C, agrega el overlay del DS3231, instala `astral`, da permisos de ejecución a los scripts, instala y habilita los servicios de systemd (`hotspot.service` y `sync-rtc.service`), y configura el crontab con las cinco tareas periódicas. Autodetecta la ubicación del repositorio y el usuario del sistema.

Ejecutarlo desde la raíz del repositorio, sin `sudo` (el script pide permisos de administrador solo donde los necesita):

```bash
cd ~/LSD-Tector2.0
./install.sh
```

Verificar que la instalación fue exitosa:

```bash
sudo systemctl status hotspot.service
sudo systemctl status sync-rtc.service
crontab -l
```

Los servicios deben aparecer habilitados y el crontab debe listar las cinco tareas. Al final, el script avisa si hace falta reiniciar — la primera vez que se corre, sí (para activar el overlay del DS3231 recién agregado).

### 5. Reiniciar y verificar el DS3231

```bash
sudo reboot
```

Después de reconectarse por SSH, verificar que el DS3231 quedó reconocido como reloj de hardware:

```bash
ls /dev/rtc*
sudo hwclock -r
```

Debe listar `/dev/rtc0` (o `/dev/rtc1` si ya hay otro RTC registrado) y devolver la hora actual sin errores.

> [!NOTE]
> Si `/dev/rtc*` no aparece, lo más probable es que el módulo DS3231 no esté bien conectado físicamente (SDA/SCL/VCC/GND) — no suele ser un problema de configuración. `dmesg | grep rtc` mostrando `probe ... failed with error -5` confirma que el software está buscando el chip correctamente pero nadie responde en el bus I2C.

Si el reloj está muy desfasado (por ejemplo, si el módulo es nuevo y nunca se sincronizó), escribirle la hora del sistema una vez de forma manual:

```bash
sudo hwclock -w
```

> [!NOTE]
> La alarma del DS3231 (usada para despertar la Raspberry desde apagado) todavía no se programa desde ningún script — ver la nota `PENDIENTE` al principio de este README y en `python/set_wake_rtc.py`.

### 6. rclone

Instalar rclone:

```bash
sudo apt install rclone
```

**Autenticación con Google Drive**

La autenticación con Google requiere un navegador con interfaz gráfica. Como BirdNET-Pi ocupa el navegador de la Raspberry Pi, la autenticación se realiza desde una PC con Windows o Linux como intermediaria.

**En la PC intermediaria:**

1. Descargar rclone para el sistema operativo correspondiente desde [https://rclone.org/downloads/](https://rclone.org/downloads/)
2. Descomprimir el archivo
3. Abrir una terminal (PowerShell en Windows) en la carpeta donde se descomprimió rclone
4. Ejecutar el siguiente comando:

```bash
.\rclone.exe authorize "drive"
```

> **Nota:** en Linux o macOS el comando es `./rclone authorize "drive"`.

5. El navegador se abrirá automáticamente. Iniciar sesión con la cuenta de Google deseada y otorgar los permisos solicitados.
6. La terminal mostrará un token JSON entre llaves (`{...}`). Copiar el token completo, incluyendo las llaves.

**En la Raspberry Pi:**

Ejecutar el asistente de configuración:

```bash
rclone config
```

Seguir el asistente interactivo con las siguientes respuestas:

- `n` → crear una nueva configuración
- Nombre: `gdrive`
- Seleccionar el número correspondiente a **Google Drive** en la lista
- `client_id`: dejar vacío y presionar Enter
- `client_secret`: dejar vacío y presionar Enter
- Scope: opción `1` (acceso completo)
- `service_account_file`: dejar vacío y presionar Enter
- Configuración avanzada: `n`
- Autenticación desde este dispositivo (auto config): `n`
- Pegar el token JSON obtenido desde la PC intermediaria
- Configurar como shared drive: `n`
- Confirmar configuración: `y`
- Salir del asistente: `q`

> **Nota sobre `client_id` y `client_secret`:** dejarlos vacíos hace que rclone utilice las credenciales OAuth por defecto, que son compartidas entre todos los usuarios de rclone. En condiciones de uso intensivo esto puede ocasionalmente generar errores del tipo `429 Too Many Requests` por exceder los límites de cuota de Google. Para uso normal del LSD-Tector (subida de pocos archivos por día) esto no representa un problema. Si se desea utilizar credenciales propias, generar un Client ID y Client Secret en Google Cloud Console siguiendo la guía oficial de rclone: [https://rclone.org/drive/#making-your-own-client-id](https://rclone.org/drive/#making-your-own-client-id).

**Verificación**

Verificar que la conexión funciona correctamente listando las carpetas de Google Drive:

```bash
rclone lsd gdrive:
```

Si el comando devuelve la lista de carpetas existentes en la cuenta de Google, la configuración fue exitosa.

### 7. Archivos de configuración

Los archivos `config_general.txt` y `config_horarios.txt` se encuentran en la carpeta `config/` del repositorio. Editarlos según las necesidades del dispositivo.

**Editar `config_general.txt`:**

```bash
nano ~/LSD-Tector2.0/config/config_general.txt
```

El archivo contiene los siguientes parámetros:

| Parámetro | Descripción |
|---|---|
| `DRIVE_PATH` | Ruta de la carpeta en Google Drive donde se sincronizan datos y configuración. Puede ser una carpeta en la raíz (ej: `LSD-Tector`) o anidada (ej: `Proyectos/LSD/Tector`). |
| `FIRST_START` | Mantener en `TRUE` para activar el modo hotspot en el primer arranque. Una vez configurada la red WiFi exitosamente, el sistema lo cambia automáticamente a `FALSE`. Si el WiFi ya se configuró a mano (por ejemplo por SSH directo), poner en `FALSE` para no disparar el portal de configuración en el próximo arranque. |
| `HOTSPOT_SSID` | Nombre de la red WiFi de configuración que emite el dispositivo en el primer arranque. |
| `HOTSPOT_PASSWORD` | Contraseña de esa red WiFi de configuración. |
| `LAT` y `LON` | Coordenadas geográficas del lugar de instalación. Pueden dejarse con valores aproximados ya que se actualizan automáticamente mediante geolocalización por IP al utilizar el modo hotspot. |

> [!NOTE]
> Los parámetros energéticos de la v1.1 (`CONSUMO_W`, `CAPACIDAD_MAH`, `VOLTAJE_BATERIA`, `MARGEN_SEGURIDAD`, `UMBRAL_BATERIA`) no están en este archivo: dependían de la PiJuice o de un watchdog de batería que todavía no existe para este hardware. El nuevo esquema por voltaje ya tiene su umbral definido (`UMBRAL_BATERIA_V=6.9`, comentado al principio del archivo junto con la justificación completa) y va a activarse cuando el INA219 esté instalado — ver la nota al principio de este README.

**Editar `config_horarios.txt`:**

```bash
nano ~/LSD-Tector2.0/config/config_horarios.txt
```

El archivo contiene los siguientes parámetros:

| Parámetro | Descripción |
|---|---|
| `AUTO_SYNC` | Mantener en `ON` para que el sistema recalcule automáticamente los horarios al final de cada ventana, usando la librería `astral` y las coordenadas del archivo `config_general.txt`. |
| `OFFSET_AMANECER_SYNC` y `OFFSET_ATARDECER_SYNC` | Offset en minutos respecto al amanecer y atardecer astronómicos. Valores positivos retrasan el inicio de la ventana, negativos la adelantan. Si no se desea offset, utilizar `0`. |
| `DURACION_AMANECER_SYNC` y `DURACION_ATARDECER_SYNC` | Duración en horas de cada ventana de grabación. Reemplazar por la duración deseada (por ejemplo, `2` para una ventana de 2 horas). |
| `INICIO_AMANECER`, `FIN_AMANECER`, `INICIO_ATARDECER`, `FIN_ATARDECER` | Se usan solo si `AUTO_SYNC` está en `OFF`. Con `AUTO_SYNC=ON`, estos horarios se calculan y completan automáticamente con `astral` a partir de las coordenadas, las duraciones y los offsets. |

> **Importante:** en ambos archivos, las variables se escriben sin espacios alrededor del signo `=` (formato `CLAVE=valor`). No modificar los nombres de las variables.

**Verificación**

Una vez editados ambos archivos, verificar que el contenido quedó correcto:

```bash
cat ~/LSD-Tector2.0/config/config_general.txt
cat ~/LSD-Tector2.0/config/config_horarios.txt
```

Revisar que todos los valores fueron completados correctamente y que se respeta el formato `CLAVE=valor` sin espacios.

### 8. Crear carpetas en Google Drive y subir archivos de configuración

Crear las carpetas que utilizará el sistema en Google Drive, usando la ruta definida en `DRIVE_PATH` (en los ejemplos siguientes se asume `DRIVE_PATH=Laboratorio 7/Tector 2`, el valor real usado por este dispositivo):

```bash
rclone mkdir "gdrive:Laboratorio 7/Tector 2"
rclone mkdir "gdrive:Laboratorio 7/Tector 2/Detecciones"
```

Subir los archivos de configuración iniciales:

```bash
rclone copy ~/LSD-Tector2.0/config/config_horarios.txt "gdrive:Laboratorio 7/Tector 2/"
rclone copy ~/LSD-Tector2.0/config/config_general.txt "gdrive:Laboratorio 7/Tector 2/"
```

Verificar que los archivos fueron subidos correctamente:

```bash
rclone ls "gdrive:Laboratorio 7/Tector 2/"
```

La salida debe listar los dos archivos de configuración.

> **Nota:** la carpeta de Google Drive se define mediante `DRIVE_PATH` en `config_general.txt`. La subcarpeta `Detecciones` es fija, y las detecciones quedan ahí directamente organizadas en subcarpetas por fecha (heredadas de la estructura que ya usa BirdNET-Pi localmente).

Con esto, el software propio del LSD-Tector (WiFi, portal de configuración, sincronización con Drive, RTC) ya está completamente operativo. Los dos pasos que siguen son sobre BirdNET-Pi, opcionales para llegar a este punto.

### 9. BirdNET-Pi

BirdNET-Pi es el motor de grabación, análisis y extracción de detecciones: LSD-Tector no reimplementa nada de eso, se apoya en su pipeline (`birdnet_recording.service` + `birdnet_analysis.service`) y en su convención de carpetas (`BirdSongs/Extracted/By_Date/`), de la que dependen directamente `cierre_amanecer.sh` y `cierre_atardecer.sh` para subir las detecciones a Drive. También se usa su integración nativa con BirdWeather.

> [!NOTE]
> Si el objetivo inmediato es solo poner en marcha la Raspberry con el software propio del LSD-Tector y dejar BirdNET-Pi para después, este paso puede saltearse: nada de los pasos anteriores depende de que esté presente. Los scripts nuevos de este repositorio (`actualizar_modelo.sh`, el chequeo de salud en los `cierre_*.sh`) detectan que no está instalado y no hacen nada.

Desde la terminal de la RP, ejecutar:

```bash
curl -s https://raw.githubusercontent.com/Nachtzuster/BirdNET-Pi/main/newinstaller.sh | bash
```

La instalación tarda varios minutos (y necesita `sudo` sin contraseña — ver paso 3). Una vez finalizada, BirdNET-Pi queda corriendo automáticamente y es accesible desde cualquier dispositivo en la misma red ingresando `http://[IP_de_la_RP]` en el navegador (antes de correr el paso 9.5, que apaga esa interfaz web para ahorrar batería). Para obtener la IP de la Raspberry Pi, ejecutar desde su terminal:

```bash
hostname -I
```

El primer valor que devuelve es la IP local del dispositivo.

### 9.5. Configurar BirdNET-Pi para uso desatendido, y cargar el modelo reentrenado

BirdNET-Pi instala por defecto un conjunto de servicios pensados para cuando alguien mira el dashboard desde el navegador en la misma red (streaming de audio en vivo, visor de espectrograma, gráficos, terminal web, panel de estadísticas). En un dispositivo desatendido en el campo no hay nadie mirando esos servicios, y miden un consumo real: apagarlos midió una reducción de **~19% en el consumo instantáneo** en pruebas de campo de la v1.1, sin afectar la grabación, el análisis ni la subida a BirdWeather, que no dependen de ninguno de ellos.

El script `configurar_birdnet.sh` hace esto de forma automática (apagar y enmascarar los servicios de dashboard/streaming, arrancar en modo consola, configurar la gestión de disco, y dejar `CONFIDENCE`/`SENSITIVITY` en los valores de partida para monitoreo continuo), y de paso pide el token de BirdWeather:

```bash
cd ~/LSD-Tector2.0
./scripts/configurar_birdnet.sh
```

Correrlo una sola vez, después de instalar BirdNET-Pi. El token de BirdWeather queda guardado en `birdnet.conf` (fuera de este repositorio, nunca se sube a GitHub).

> [!NOTE]
> El modelo reentrenado (las 193 especies locales, además del catálogo global de BirdNET sin modificar) se instala aparte, automáticamente, mediante `actualizar_modelo.sh`: se corre solo en cada ventana de grabación (junto con `actualizar_repo.sh`) y actualiza el `.tflite` cada vez que hay una versión nueva en [`LSDTector-BirdNET-retrain-bsas`](https://github.com/LSDArroyoGold/LSDTector-BirdNET-retrain-bsas), sin necesidad de reinstalar nada a mano. Para forzarlo de inmediato en vez de esperar a la próxima ventana: `bash ~/LSD-Tector2.0/scripts/actualizar_modelo.sh`.

> [!NOTE]
> Además del modelo universal, `LSDTector-BirdNET-retrain-bsas` permite generar una versión ajustada a la región del dispositivo: a cada una de las 193 especies locales se le suma un sesgo según su frecuencia real de observación en esa región (nunca la descarta, solo la refuerza o atenúa). Corre solo, vía `scripts/aplicar_ajuste_regional.sh` (agregado junto a `actualizar_modelo.sh` en `inicio_amanecer.sh`/`inicio_atardecer.sh`), pero necesita el entorno `~/birdnet-v2-env` (`bash instalar.sh` dentro de un clon de `LSDTector-BirdNET-retrain-bsas`) y que ya exista un archivo de frecuencias para esa región en ese repositorio. Sin esos dos requisitos, sigue con el modelo universal sin ajustar, que es siempre el comportamiento por defecto. Ningún dispositivo se conecta a eBird para esto, ver el README de ese repositorio para el detalle.

> [!NOTE]
> `LATITUDE`/`LONGITUDE` en `birdnet.conf` (usadas por BirdNET-Pi para su filtro de especies plausibles por región y época) se sincronizan automáticamente con `LAT`/`LON` de `config_general.txt` cuando corre `hotspot.sh` — es decir, recién en el primer arranque con `FIRST_START=TRUE` (paso 7), o si el WiFi se configuró por ese camino. Si el WiFi se configuró a mano (SSH directo, sin pasar por el portal), `birdnet.conf` queda con las coordenadas por defecto del instalador de BirdNET-Pi hasta que se corrijan manualmente: `sudo nano ~/BirdNET-Pi/birdnet.conf`, buscar `LATITUDE`/`LONGITUDE`.

---

## Primer arranque en campo

Una vez completados todos los pasos de instalación, el dispositivo está listo para ser desplegado en campo. El procedimiento de primer arranque es el siguiente:

1. Verificar que en `config_general.txt` el parámetro `FIRST_START` está en `TRUE`.
2. Encender la Raspberry Pi. Esperar aproximadamente 30 segundos a que el sistema arranque completamente y se active el servicio `hotspot.service`.
3. Desde un celular o computadora, buscar redes WiFi disponibles. Conectarse a la red de configuración (nombre y contraseña definidos en `HOTSPOT_SSID` y `HOTSPOT_PASSWORD` de `config_general.txt`).
4. Abrir un navegador web y navegar a `http://192.168.4.1:5000`. Se mostrará el portal de configuración.
5. Seleccionar de la lista la red WiFi a la que se conectará el dispositivo en campo. Ingresar la contraseña correspondiente. Presionar **Conectar**.
6. El dispositivo se desconecta del modo hotspot e intenta conectarse a la red indicada. Si la conexión es exitosa:
   - Las coordenadas geográficas se actualizan automáticamente mediante geolocalización por IP (y se propagan a `birdnet.conf` si BirdNET-Pi está instalado).
   - Los horarios de amanecer y atardecer se calculan y se escriben en `config_horarios.txt`.
   - El parámetro `FIRST_START` se cambia a `FALSE`.
   - El dispositivo calcula el horario de la próxima ventana de grabación y **queda encendido** (todavía no hay circuito de corte de energía — ver la nota al principio de este README).
7. Si la conexión falla, la red de configuración vuelve a aparecer automáticamente. Reconectarse y reintentar con las credenciales correctas.

A partir de este momento, el dispositivo opera de forma autónoma siguiendo el ciclo programado de ventanas de grabación, permaneciendo encendido de forma continua entre ellas.

> [!NOTE]
> Si el WiFi ya se configuró a mano durante la instalación (por ejemplo, por SSH directo sin pasar por el portal), este procedimiento no hace falta: dejar `FIRST_START=FALSE` y el dispositivo arranca operando directamente, sin intentar levantar el hotspot.

---

## Control remoto via Google Drive

Una vez el dispositivo está en operación en campo, los archivos `config_horarios.txt` y `config_general.txt` en la carpeta de Google Drive definida por `DRIVE_PATH` pueden editarse desde cualquier lugar para modificar la configuración del dispositivo. Los cambios se aplican en el siguiente ciclo, cuando el dispositivo descarga la versión actualizada de Drive al final de la ventana de grabación.

El archivo `log_sistema.txt` se sube a Drive al final de cada ventana y permite monitorear el estado del dispositivo de forma remota: cantidad de detecciones registradas y eventuales cierres sin conectividad. El campo de batería en cada entrada figura como `N/A` hasta que el INA219 esté instalado — ver la nota al principio de este README.

Si BirdNET-Pi está instalado, cada cierre de ventana también chequea que `birdnet_recording.service` y `birdnet_analysis.service` sigan activos, y deja una línea `ALERTA: servicios de BirdNET-Pi caidos: ...` en el log si alguno se cayó. systemd ya los reinicia solo (`Restart=always`), así que esta alerta no es para arreglarlos: es para enterarse por Drive de un problema persistente sin tener que esperar a volver al campo y notar la falta de detecciones.

Junto con `log_sistema.txt` también se sube `log_reciente.txt`, con el mismo contenido pero filtrado a solo los últimos 2 días — pensado para revisar la actividad reciente sin tener que scrollear todo el historial completo.

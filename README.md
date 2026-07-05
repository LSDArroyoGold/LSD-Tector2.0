# LSD-Tector 1.0 — Software (ACTUALIZAR README)

Este repositorio contiene todo el software necesario para replicar el sistema de monitoreo autónomo de aves LSD-Tector, desarrollado en el Laboratorio de Sistemas Dinámicos (LSD), Facultad de Ciencias Exactas y Naturales, Universidad de Buenos Aires.

El sistema gestiona automáticamente ventanas de grabación en horarios de amanecer y atardecer, identifica especies mediante BirdNET-Pi, envía detecciones a Google Drive, y administra el ciclo de encendido y apagado de la Raspberry Pi mediante el RTC de la PiJuice HAT. Para una descripción completa del hardware y el diseño físico del dispositivo, referirse al artículo asociado.

Este software fue desarrollado y probado sobre una **Raspberry Pi 4 Model B (4GB RAM)** con una **PiJuice HAT** como módulo de gestión de energía. No se garantiza compatibilidad con otros modelos o configuraciones de hardware.

---

## Dependencias

- Raspberry Pi OS Full 64-bit (Bookworm)
- BirdNET-Pi
- Python 3 (incluido en Raspberry Pi OS)
- rclone
- astral (librería Python)
- API Python de PiJuice
- nmcli (incluido en Raspberry Pi OS)
- dnsmasq y util-linux-extra

### 1. Sistema operativo

Instalar **Raspberry Pi OS Full 64-bit (Bookworm)** en la microSD usando [Raspberry Pi Imager](https://www.raspberrypi.com/software/). Durante el proceso de flasheo, en la sección de configuración avanzada del Imager (ícono del engranaje), crear un usuario con nombre y contraseña a elección.

> [!WARNING]
> Todos los scripts y archivos de configuración de este repositorio tienen la ruta `/home/lsd/` hardcodeada como directorio de trabajo. Esta ruta corresponde al usuario `lsd` utilizado en nuestra instalación de referencia. Si se utiliza un nombre de usuario diferente, será necesario reemplazar manualmente **todas las apariciones** de `/home/lsd/` por la ruta correspondiente al usuario elegido, en cada uno de los scripts `.sh` y `.py` del repositorio antes de utilizarlos. En versiones futuras esta configuración será centralizada y más fácil de personalizar.

Una vez flasheada la microSD, insertarla en la Raspberry Pi y encenderla.

### 2. BirdNET-Pi

Desde la terminal de la RP, ejecutar:

```bash
curl -s https://raw.githubusercontent.com/Nachtzuster/BirdNET-Pi/main/newinstaller.sh | bash
```

La instalación tarda varios minutos. Una vez finalizada, BirdNET-Pi queda corriendo automáticamente y es accesible desde cualquier dispositivo en la misma red ingresando `http://[IP_de_la_RP]` en el navegador. Para obtener la IP de la Raspberry Pi, ejecutar desde su terminal:

```bash
hostname -I
```

El primer valor que devuelve es la IP local del dispositivo.

Una vez instalado, configurar la gestión de disco para evitar que la tarjeta microSD se llene con el tiempo:

```bash
sudo nano /etc/birdnet/birdnet.conf
```
Buscar los parámetros `FULL_DISK` y `PURGE_THRESHOLD` y establecerlos así:

```
FULL_DISK=purge
PURGE_THRESHOLD=75
```
Con esta configuración, cuando el disco supere el 75% de ocupación, BirdNET-Pi eliminará automáticamente las grabaciones del día más antiguo para liberar espacio. Guardar con **Ctrl+O** y salir con **Ctrl+X**.

### 3. Paquetes del sistema

```bash
sudo apt update
sudo apt install -y dnsmasq util-linux-extra
sudo systemctl enable dnsmasq
sudo systemctl start dnsmasq
```

Verificar que `hwclock` quedó disponible:

```bash
which hwclock
```

Debe devolver `/usr/sbin/hwclock`.

### 4. Habilitar I2C

La PiJuice se comunica con la Raspberry Pi mediante el protocolo I2C. Para habilitarlo:

```bash
sudo raspi-config
```

Navegar a **Interface Options → I2C → Enable**. Confirmar y salir. Luego reiniciar:

```bash
sudo reboot
```

Verificar que la PiJuice es detectada correctamente en el bus I2C (debe aparecer `14` en la dirección 0x14):

```bash
sudo i2cdetect -y 1
```

### 5. Dependencias Python

```bash
pip install astral --break-system-packages
```

### 6. API Python de PiJuice

El paquete oficial de PiJuice no está disponible en los repositorios estándar de Raspberry OS. Instalarlo directamente desde GitHub:

```bash
git clone https://github.com/PiSupply/PiJuice.git /home/lsd/BirdNET-Pi/PiJuice
cd /home/lsd/BirdNET-Pi/PiJuice/Software/Source
pip install . --break-system-packages
```

Verificar que la API funciona correctamente:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.status.GetStatus())
print(pj.status.GetChargeLevel())
"
```

Si la PiJuice responde sin errores, la instalación fue exitosa.

### 7. Clonar el repositorio

Clonar este repositorio en la Raspberry Pi:

```bash
cd /home/lsd
git clone https://github.com/LSDArroyoGold/LSD-Tector-1.0.git
```

Copiar los scripts y archivos de configuración a `/home/lsd/`:

```bash
cp /home/lsd/LSD-Tector-1.0/scripts/* /home/lsd/
cp /home/lsd/LSD-Tector-1.0/python/* /home/lsd/
cp /home/lsd/LSD-Tector-1.0/config/* /home/lsd/
chmod +x /home/lsd/*.sh
```

> **Nota:** el asterisco `*` es un comodín de bash que significa "todos los archivos". Por ejemplo, `scripts/*` copia todos los archivos dentro de la carpeta `scripts/`.

Copiar los archivos de servicio de systemd:

```bash
sudo cp /home/lsd/LSD-Tector-1.0/systemd/sync-rtc.service /etc/systemd/system/
sudo cp /home/lsd/LSD-Tector-1.0/systemd/hotspot.service /etc/systemd/system/
```

Dar permisos correctos a los archivos de servicio:

```bash
sudo chmod 644 /etc/systemd/system/sync-rtc.service
sudo chmod 644 /etc/systemd/system/hotspot.service
```

Recargar la configuración de systemd para que reconozca los nuevos servicios:

```bash
sudo systemctl daemon-reload
```

### 8. rclone

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

### 9. Archivos de configuración

Los archivos `config_general.txt` y `config_horarios.txt` ya fueron copiados a `/home/lsd/` en el paso 7. Ahora hay que editarlos según las necesidades del dispositivo.

**Editar `config_general.txt`:**

```bash
nano /home/lsd/config_general.txt
```

El archivo contiene los siguientes parámetros:

```
FIRST_START = TRUE

LAT=<latitud_inicial>
LON=<longitud_inicial>

CONSUMO_W = <potencia_consumida_estimada_en_W>
CAPACIDAD_MAH = <capacidad_bateria_en_mAh>
VOLTAJE_BATERIA = <voltaje_nominal_bateria>
MARGEN_SEGURIDAD = <factor_de_seguridad>
```

Descripción de cada parámetro y cómo completarlo:

| Parámetro | Descripción |
|---|---|
| `FIRST_START` | Mantener en `TRUE` para activar el modo hotspot en el primer arranque. Una vez configurada la red WiFi exitosamente, el sistema lo cambia automáticamente a `FALSE`. |
| `LAT` y `LON` | Coordenadas geográficas del lugar de instalación. Pueden dejarse con valores aproximados ya que se actualizan automáticamente mediante geolocalización por IP al utilizar el modo hotspot. |
| `CONSUMO_W` | Potencia consumida estimada del sistema durante una ventana de grabación, en W. Reemplazar por el valor medido del sistema. |
| `CAPACIDAD_MAH` | Capacidad nominal de la batería en mAh. Reemplazar por la capacidad de la batería utilizada. |
| `VOLTAJE_BATERIA` | Voltaje nominal de la batería en V. Para baterías LiPo de celda única, utilizar `3.7`. |
| `MARGEN_SEGURIDAD` | Factor multiplicador aplicado al umbral de batería para garantizar margen de operación. Valor recomendado: `1.5`. |

> **Importante:** respetar el formato de cada línea. Las variables `LAT` y `LON` no llevan espacios alrededor del signo `=`. El resto de las variables sí llevan espacios.

**Editar `config_horarios.txt`:**

```bash
nano /home/lsd/config_horarios.txt
```

El archivo contiene los siguientes parámetros:

```
inicio_amanecer = 06:00
fin_amanecer = 08:00
inicio_atardecer = 17:00
fin_atardecer = 19:00

AUTO_SYNC=ON
duracion_amanecer_sync=<duracion_en_horas>
offset_amanecer_sync=<offset_en_minutos>
duracion_atardecer_sync=<duracion_en_horas>
offset_atardecer_sync=<offset_en_minutos>
```

Descripción de cada parámetro y cómo completarlo:

| Parámetro | Descripción |
|---|---|
| `inicio_amanecer`, `fin_amanecer`, `inicio_atardecer`, `fin_atardecer` | Los valores que se muestran son simplemente valores iniciales. Estos horarios se calculan y completan automáticamente con `astral` a partir de las coordenadas geográficas, las duraciones y los offsets configurados. |
| `AUTO_SYNC` | Mantener en `ON` para que el sistema recalcule automáticamente los horarios al final de cada ventana, usando la librería `astral` y las coordenadas del archivo `config_general.txt`. |
| `duracion_amanecer_sync` y `duracion_atardecer_sync` | Duración en horas de cada ventana de grabación. Reemplazar por la duración deseada (por ejemplo, `2` para una ventana de 2 horas). |
| `offset_amanecer_sync` y `offset_atardecer_sync` | Offset en minutos respecto al amanecer y atardecer astronómicos. Valores positivos retrasan el inicio de la ventana, negativos la adelantan. Si no se desea offset, utilizar `0`. |

> **Importante:** respetar el formato de cada línea. Las primeras cuatro variables (`inicio_amanecer`, `fin_amanecer`, `inicio_atardecer`, `fin_atardecer`) llevan espacios alrededor del signo `=`. Las demás no llevan espacios.

**Verificación**

Una vez editados ambos archivos, verificar que el contenido quedó correcto:

```bash
cat /home/lsd/config_general.txt
cat /home/lsd/config_horarios.txt
```

Revisar que todos los valores fueron reemplazados correctamente, que los espacios alrededor del signo `=` respetan el formato indicado, y que no quedaron placeholders del tipo `<...>` sin reemplazar.
### 10. Configurar el perfil de batería en la PiJuice

Este paso le indica a la PiJuice las características de la batería conectada para que el fuel gauge y el gestor de carga funcionen correctamente. Ejecutar el script provisto:

```bash
python3 /home/lsd/configurar_bateria_pijuice.py
```

> **Nota:** los parámetros del perfil de batería están definidos dentro del script `configurar_bateria_pijuice.py`. Si se utiliza una batería con características distintas (capacidad, voltaje de regulación, voltaje de corte, etc.), modificar los valores correspondientes en el script antes de ejecutarlo.

Verificar que el perfil quedó correctamente aplicado:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
print(pj.config.GetBatteryProfile())
"
```

La salida debe mostrar los parámetros configurados en el script.

### 11. Configurar el comportamiento de encendido de la PiJuice

Por defecto, la PiJuice enciende automáticamente la Raspberry Pi al detectar alimentación externa (por ejemplo, cuando el panel solar empieza a entregar potencia al amanecer). Este comportamiento no es deseado en el sistema LSD-Tector, donde la RP solo debe encenderse mediante la alarma programada del RTC.

Para deshabilitar el encendido automático, ejecutar:

```bash
python3 -c "
import sys
sys.path.append('/home/lsd/BirdNET-Pi/PiJuice/Software/Source')
from pijuice import PiJuice
pj = PiJuice(1, 0x14)
config = pj.config.GetPowerInputsConfig()['data']
config['no_battery_turn_on'] = True
pj.config.SetPowerInputsConfig(config)
print(pj.config.GetPowerInputsConfig())
"
```

La salida debe mostrar `'no_battery_turn_on': True`.


### 12. Habilitar la sincronización del reloj al arranque

La Raspberry Pi 4 no tiene reloj de tiempo real propio. La PiJuice registra su RTC como `rtc0` en el sistema, y ese RTC es el que conserva la hora cuando el dispositivo está apagado entre ventanas. El servicio `sync-rtc.service` copia la hora del RTC al reloj del sistema en cada arranque, mediante `hwclock --hctosys`.

Esto es imprescindible para la operación en campo: la PiJuice despierta a la Raspberry Pi a la hora programada, y este servicio garantiza que el reloj del sistema tenga la hora real correcta antes de que el crontab evalúe los horarios de las ventanas. Sin esta sincronización, tras un arranque sin conexión a internet el reloj del sistema quedaría con la hora del último apagado y las ventanas no dispararían a la hora correcta.

El archivo del servicio ya fue copiado a `/etc/systemd/system/` en el paso 7. Habilitarlo:

```bash
sudo systemctl enable sync-rtc.service
sudo systemctl start sync-rtc.service
```

Verificar que está activo:

```bash
sudo systemctl status sync-rtc.service
```

La salida debe indicar `active (exited)` o similar, sin errores.


### 13. Habilitar el servicio hotspot

El servicio `hotspot.service` ejecuta el script `hotspot.sh` al arrancar el sistema. Este script verifica si `FIRST_START=TRUE` en `config_general.txt` y, en ese caso, activa el modo hotspot para configurar la red WiFi. El archivo del servicio ya fue copiado a `/etc/systemd/system/` en el paso 7. Habilitarlo:

```bash
sudo systemctl enable hotspot.service
```

> **Nota:** no es necesario ejecutar `start` sobre este servicio en este momento. Se ejecutará automáticamente en el próximo arranque de la Raspberry Pi.

### 14. Configurar el crontab

El crontab define las tareas periódicas del sistema. Los cuatro scripts principales (`cierre_amanecer.sh`, `cierre_atardecer.sh`, `inicio_amanecer.sh`, `inicio_atardecer.sh`) y la rutina del botón deben ejecutarse cada minuto. Cada uno verifica internamente si la hora actual coincide con su horario configurado y, de ser así, ejecuta su rutina.

Abrir el crontab del usuario `lsd`:

```bash
crontab -e
```

> **Importante:** no utilizar `sudo` con este comando. El crontab debe pertenecer al usuario `lsd`, no a root.

La primera vez que se ejecuta, el sistema pregunta qué editor utilizar. Seleccionar `nano` (opción 1).

Al final del archivo, agregar las siguientes líneas:

```
* * * * * /home/lsd/cierre_amanecer.sh
* * * * * /home/lsd/cierre_atardecer.sh
* * * * * /home/lsd/inicio_amanecer.sh
* * * * * /home/lsd/inicio_atardecer.sh
* * * * * python3 /home/lsd/check_button.py
```

Guardar con **Ctrl+O**, Enter, y salir con **Ctrl+X**.

Verificar que las tareas quedaron registradas:

```bash
crontab -l
```

La salida debe mostrar las cinco líneas agregadas.

Verificar también que el servicio cron está activo en el sistema:

```bash
sudo systemctl status cron
```

La salida debe mostrar `active (running)`. Si no estuviera activo, iniciarlo y habilitarlo para que arranque automáticamente con el sistema:

```bash
sudo systemctl enable cron
sudo systemctl start cron
```

### 15. Crear carpetas en Google Drive y subir archivos de configuración

Crear las carpetas que utilizará el sistema en Google Drive:

```bash
rclone mkdir "gdrive:Laboratorio 6"
rclone mkdir "gdrive:Laboratorio 6/BirdNET_Detecciones"
```

Subir los archivos de configuración iniciales:

```bash
rclone copy /home/lsd/config_horarios.txt "gdrive:Laboratorio 6/"
rclone copy /home/lsd/config_general.txt "gdrive:Laboratorio 6/"
```

Verificar que los archivos fueron subidos correctamente:

```bash
rclone ls "gdrive:Laboratorio 6/"
```

La salida debe listar los dos archivos de configuración.

> **Nota:** los nombres de las carpetas en Google Drive (`Laboratorio 6` y `BirdNET_Detecciones`) están definidos por los scripts del sistema. Si se desea utilizar nombres diferentes, modificar las referencias correspondientes en todos los scripts antes de ejecutarlos.

---

## Primer arranque en campo

Una vez completados todos los pasos de instalación, el dispositivo está listo para ser desplegado en campo. El procedimiento de primer arranque es el siguiente:

1. Verificar que en `/home/lsd/config_general.txt` el parámetro `FIRST_START` está en `TRUE`.
2. Encender la Raspberry Pi. Esperar aproximadamente 30 segundos a que el sistema arranque completamente y se active el servicio `hotspot.service`.
3. Desde un celular o computadora, buscar redes WiFi disponibles. Conectarse a la red **BirdNET-Setup** con la contraseña `birdnet123`.
4. Abrir un navegador web y navegar a `http://192.168.4.1:5000`. Se mostrará el portal de configuración.
5. Seleccionar de la lista la red WiFi a la que se conectará el dispositivo en campo. Ingresar la contraseña correspondiente. Presionar **Conectar**.
6. El dispositivo se desconecta del modo hotspot e intenta conectarse a la red indicada. Si la conexión es exitosa:
   - Las coordenadas geográficas se actualizan automáticamente mediante geolocalización por IP.
   - Los horarios de amanecer y atardecer se calculan y se escriben en `config_horarios.txt`.
   - El parámetro `FIRST_START` se cambia a `FALSE`.
   - El dispositivo programa la alarma para la próxima ventana de grabación y se apaga.
7. Si la conexión falla, la red `BirdNET-Setup` vuelve a aparecer automáticamente. Reconectarse y reintentar con las credenciales correctas.

A partir de este momento, el dispositivo opera de forma completamente autónoma siguiendo el ciclo programado de ventanas de grabación.

---

## Control remoto via Google Drive

Una vez el dispositivo está en operación en campo, los archivos `config_horarios.txt` y `config_general.txt` en la carpeta `Laboratorio 6` de Google Drive pueden editarse desde cualquier lugar para modificar la configuración del dispositivo. Los cambios se aplican en el siguiente ciclo, cuando el dispositivo descarga la versión actualizada de Drive al final de la ventana de grabación.

El archivo `log_sistema.txt` se sube a Drive al final de cada ventana y permite monitorear el estado del dispositivo de forma remota: nivel de batería, cantidad de detecciones registradas, y eventuales cancelaciones por nivel de batería insuficiente.


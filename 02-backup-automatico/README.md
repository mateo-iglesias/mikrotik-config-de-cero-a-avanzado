# Módulo 02 – Backup automático

> Equipo: MikroTik hAP lite (RB941-2nD) · RouterOS 7.24.6 (long-term) · Configuración desde Winbox

## 1. Qué se hace y por qué

Un router sin backup es una configuración que se pierde con el primer reset, corte de luz que dañe la flash o error humano. En este módulo el router genera **todos los días, solo**, dos copias de su configuración:

| Archivo | Qué es | Para qué sirve | Riesgo |
|---|---|---|---|
| `.backup` | "Foto" binaria completa: usuarios, contraseñas, llaves, certificados | Restauración rápida en el **mismo modelo y versión** | Contiene secretos → **siempre cifrado** (`aes-sha256`) |
| `.rsc` (export) | "Plano" en texto con los comandos de configuración | Leer, comparar cambios, migrar a **otro equipo o versión** | En v7 **no incluye secretos** por defecto |

Se necesitan los dos: uno para recuperar rápido y otro para entender, auditar y migrar.

**Dos piezas:**
- **Script** (`backup-diario`) = la receta: *qué* hacer.
- **Scheduler** (`sched-backup-diario`) = la alarma: *cuándo* hacerlo (equivalente a `cron` en Linux o al Programador de tareas en Windows).

## 2. Diseño

| Elemento | Valor | Motivo |
|---|---|---|
| Nombre de archivos | `backup-lab` (fijo) | Cada ejecución sobrescribe la anterior → la flash de 16 MB no se llena |
| Cifrado del backup | `aes-sha256` + contraseña | El `.backup` lleva todos los secretos |
| Policies (script y scheduler) | `ftp, read, write, policy, test, sensitive` | Mínimo privilegio; el scheduler necesita **al menos** las mismas que el script |
| Hora | `03:00`, cada `1d` | Poco tráfico; el `/export` es lento en un CPU SMIPS de 650 MHz |
| Frecuencia | 1 vez al día | Cada escritura desgasta la flash (*Sector Writes*); diario es despreciable |
| Protección | Evita ejecuciones simultáneas | Dos ejecuciones a la vez pueden dejar un `.rsc` cortado |
| Copia externa | Correo y/o SFTP (opcionales, desactivados) | Un backup que solo vive en el router muere con el router |

Tamaño de referencia en el laboratorio: `.backup` ≈ 28 KiB, `.rsc` ≈ 3.7 KB. Espacio libre antes del módulo: 7.8 MiB.

## 3. Pasos en Winbox

### 3.1 Revisar espacio
**System → Resources** → anotar *Free HDD Space*.
**Files** → borrar solo archivos que reconozcas como basura (backups viejos, `.npk` sobrantes).

### 3.2 Backup y export manuales (para entender)
- **Files → Backup** → Name `backup-lab`, Password (guárdala en tu gestor de contraseñas), Encryption `aes-sha256`, *Don't Encrypt* sin marcar → **Backup**.
- **New Terminal** → `/export file=export-lab` → aparece `export-lab.rsc` (bórralo después).

### 3.3 Crear el script
**System → Scripts → +**
- Name: `backup-diario`
- Policy: solo `ftp`, `read`, `write`, `policy`, `test`, `sensitive`
- Source: el bloque `source={ ... }` del archivo `backup-automatico.rsc`, con tu clave
- **Run Script** para probarlo.

### 3.4 Crear el scheduler
**System → Scheduler → +**
- Name: `sched-backup-diario`
- Start Time: `03:00:00`
- Interval: `1d 00:00:00`
- Policy: las mismas del script
- On Event: `/system script run backup-diario`

**Prueba:** poner temporalmente *Start Time* 2 minutos después de la hora del router (**System → Clock**), esperar, revisar Log y Files, y volver a dejarlo en `03:00:00`.

## 4. Aplicar el script

1. Editar `backup-automatico.rsc` y cambiar los `CAMBIAR_AQUI` (como mínimo la clave del backup).
2. **Files** → arrastrar el archivo.
3. **New Terminal**:
   ```
   /import backup-automatico.rsc
   ```
4. Probar:
   ```
   /system script run backup-diario
   ```

> Si ya existen `backup-diario` o `sched-backup-diario`, el script los **reemplaza**.
> Si la clave se queda en `CAMBIAR_AQUI`, el backup no se ejecuta y deja un error en el log (a propósito).

**Caracteres prohibidos en las claves dentro del script:** `"` `$` `\` `?` (tienen significado especial en RouterOS). Mejor una clave larga (16+) que rara.

## 5. Verificación

| Dónde | Qué debe verse |
|---|---|
| **Log** | `backup-diario: OK backup-lab` |
| **Files** | `backup-lab.backup` y `backup-lab.rsc` con hora reciente; ningún `.in_progress` al terminar |
| **System → Scheduler** | *Run Count* aumenta; *Next Run* = mañana `03:00:00` |
| **System → Scripts** | *Run Count* de `backup-diario` aumenta |

Terminal:
```
/system scheduler print detail where name="sched-backup-diario"
/file print where name~"backup-lab"
/log print where message~"backup-diario"
```

## 6. Restaurar (lo que da sentido al backup)

Un backup que nunca se ha restaurado **no está comprobado**. Probar en laboratorio:

- **`.backup` (mismo equipo y versión):** **Files** → seleccionar `backup-lab.backup` → **Restore** → contraseña → el router reinicia con esa configuración.
- **`.rsc` (otro equipo o versión):** revisar el archivo (nombres de interfaces, secretos que no vienen incluidos), hacer reset **sin configuración por defecto** y luego `/import backup-lab.rsc`. Después volver a poner a mano las contraseñas (WiFi, usuarios).

> ⚠️ Restaurar reemplaza la configuración actual y puede cortar el acceso. Hazlo con cable y teniendo a mano el `.rsc` y la clave.

## 7. Copia fuera del router (opcional)

Regla **3-2-1**: 3 copias, en 2 medios distintos y 1 fuera del sitio. Mientras los archivos estén solo en la flash, si el router muere, el backup muere con él.

### 7.1 Correo (Gmail)
- Cuenta **dedicada** solo para backups (no la personal).
- Activar verificación en 2 pasos → crear una **contraseña de aplicación** (16 letras, solo sirve para enviar correo y se revoca cuando quieras).
- En el `.rsc`: quitar el `#` de la línea `/tool e-mail set ...`, completar los datos y poner `enviarCorreo true` y `correoDestino`.
- Winbox equivalente: **Tools → Email** → Server `smtp.gmail.com`, Port `587`, TLS `starttls`.
- Ventaja: el destino siempre está disponible. Es seguro enviarlo porque el `.backup` va cifrado y el `.rsc` no lleva secretos.

### 7.2 SFTP a un PC de la LAN
El router "empuja" los archivos con `/tool fetch upload=yes mode=sftp`. `fetch` se autentica con **usuario y contraseña**, así que en el PC se crea un **buzón encerrado**:
- usuario que **solo** puede usar SFTP (`ForceCommand internal-sftp`, sin shell);
- dentro de una **jaula** (`ChrootDirectory`): solo ve su carpeta;
- escribe únicamente en `subidas/`;
- firewall del PC que acepta el puerto 22 **solo desde `192.168.10.1`**;
- IP fija del PC (**IP → DHCP Server → Leases → Make Static**).

En el PC los archivos quedan con fecha (`2026-11-10-backup-lab.backup`), así que se conserva un **historial** sin llenar el router.

**Ubuntu (resumen):**
```bash
sudo apt install -y openssh-server
sudo groupadd sftponly
sudo mkdir -p /srv/sftp/mtbackup/subidas
sudo useradd -s /usr/sbin/nologin -G sftponly -d /srv/sftp/mtbackup mtbackup
sudo passwd mtbackup
sudo chown root:root /srv/sftp/mtbackup && sudo chmod 755 /srv/sftp/mtbackup
sudo chown mtbackup:mtbackup /srv/sftp/mtbackup/subidas && sudo chmod 700 /srv/sftp/mtbackup/subidas
```
`/etc/ssh/sshd_config.d/sftponly.conf`:
```
Match Group sftponly
    ChrootDirectory %h
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
```
`sudo sshd -t && sudo systemctl restart ssh`

**Windows 10/11 (resumen, PowerShell como administrador):**
```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd; Set-Service sshd -StartupType Automatic
$p = Read-Host -AsSecureString "Clave para mtbackup"
New-LocalUser -Name mtbackup -Password $p -PasswordNeverExpires -AccountNeverExpires
New-Item -ItemType Directory -Path C:\SFTP\mtbackup\subidas -Force
icacls C:\SFTP\mtbackup /inheritance:r /grant "*S-1-5-32-544:(OI)(CI)F" "*S-1-5-18:(OI)(CI)F" "mtbackup:(RX)"
icacls C:\SFTP\mtbackup\subidas /grant "mtbackup:(OI)(CI)M"
Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -RemoteAddress 192.168.10.1
```
Al final de `C:\ProgramData\ssh\sshd_config`:
```
Match User mtbackup
    ChrootDirectory C:\SFTP\mtbackup
    ForceCommand internal-sftp
    AllowTcpForwarding no
    PermitTTY no
    X11Forwarding no
```
`Restart-Service sshd` · El usuario **no** debe estar en Administradores. (Se usan SID porque en Windows en español el grupo se llama "Administradores".)

**En el `.rsc`:** `enviarSftp true`, `sftpIp`, `sftpUser`, `sftpClave`.

> ⚠️ El PC destino debe estar **encendido** a la hora del scheduler. Si no lo está a las 03:00, cambia la hora (por ejemplo, 20:00).

## 8. Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `not enough permissions` en el log | Al scheduler le faltan policies del script | Mismas policies en los dos |
| Archivo `.rsc.in_progress` | El export todavía se está escribiendo (lento en SMIPS) | Esperar; el script ya espera hasta 120 s |
| Dos ejecuciones casi seguidas | Al cambiar *Start Time* a una hora pasada o actual, la tarea se dispara | El script omite la segunda ejecución y avisa con `warning` |
| `.backup` y `.rsc` con horas muy distintas | El `/export` tarda decenas de segundos | Normal en el hAP lite |
| Log vacío tras reiniciar | El log está en `memory` (RAM) | Syslog remoto en el módulo 06 |
| Scheduler no corre a la hora | Reloj mal | Revisar NTP (módulo 01) y **System → Clock** |
| La clave del script "no funciona" | Usaste `"` `$` `\` o `?` | Cambiar la clave |
| Correo no llega | Contraseña de aplicación mal copiada, 2FA inactivo o sin DNS | Revisar Log (`e-mail`) y **Tools → Email** |
| SFTP falla | PC apagado, firewall del PC o permisos de la jaula | Probar `sftp mtbackup@IP` desde otro equipo de la LAN |

## 9. Notas de seguridad

- **Cifra siempre el `.backup`**: sin cifrar, quien lo obtenga tiene usuarios, WiFi y llaves.
- **Guarda la clave del backup en un gestor de contraseñas**: sin ella el archivo es inútil.
- La clave queda **en texto plano dentro del script**: solo debe haber usuarios de confianza con permiso `read`/`sensitive` (en el módulo 01 dejamos un único usuario `full` limitado a la LAN).
- **Nunca subas a GitHub** un `.backup` ni un export con `show-sensitive`. Antes de publicar un `.rsc`, quita el *serial number* y el *software id*.
- Credenciales externas (Gmail, SFTP) **dedicadas y revocables**: cuenta de correo exclusiva, contraseña de aplicación y buzón SFTP sin shell, en jaula y con firewall.
- Un backup solo dentro del router **no** protege contra fallas del router: activa al menos una copia externa.
- **Prueba la restauración**: un backup no probado no es un backup confiable.

---

⬅️ [Módulo 01 – Configuración base](../01-configuracion-base/) · 🏠 [Inicio](../README.md) · ➡️ [Módulo 03 – Acceso remoto](../03-acceso-remoto/)

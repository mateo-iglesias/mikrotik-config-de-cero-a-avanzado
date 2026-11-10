# =====================================================================
# Modulo 02 - Backup automatico
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo:      MikroTik hAP lite (RB941-2nD, SMIPS, 16 MB flash)
# Probado en:  RouterOS 7.24.6 (long-term)
# ---------------------------------------------------------------------
# Que hace:
#  - Crea el script "backup-diario":
#      * .backup cifrado (aes-sha256) -> restauracion rapida, mismo equipo
#      * export .rsc sin secretos     -> legible, portable, comparable
#    Ambos con NOMBRE FIJO: cada ejecucion reemplaza la anterior y la
#    flash de 16 MB no se llena.
#  - Crea el scheduler "sched-backup-diario": todos los dias a las 03:00.
#  - Opcional (desactivado): envio por correo y/o por SFTP a un PC.
#
# Uso:
#  1. Cambia los valores CAMBIAR_AQUI (como minimo la clave del backup).
#     No uses en las claves los caracteres:  "  $  \  ?
#  2. Sube este archivo en Winbox -> Files.
#  3. New Terminal:  /import backup-automatico.rsc
#  4. Prueba:        /system script run backup-diario
#     y revisa Log y Files.
#
# OJO: si ya existen un script "backup-diario" o un scheduler
# "sched-backup-diario", este archivo los REEMPLAZA.
# =====================================================================

:delay 15s

# ---------- Limpieza (permite volver a importar sin duplicar) ----------
/system script remove [find name="backup-diario"]
/system scheduler remove [find name="sched-backup-diario"]

# ---------- Opcional: servidor de correo (Gmail) ----------
# Usa una cuenta dedicada y una "contrasena de aplicacion" de 16 letras.
# Quita el # de la siguiente linea para activarlo:
# /tool e-mail set server=smtp.gmail.com port=587 tls=starttls from="CAMBIAR_AQUI" user="CAMBIAR_AQUI" password="CAMBIAR_AQUI"

# ---------- Script de backup ----------
/system script add name=backup-diario \
    policy=ftp,read,write,policy,test,sensitive \
    comment="Modulo 02 - backup cifrado + export diario" \
    source={
:local nombre "backup-lab"
:local clave "CAMBIAR_AQUI"

:local enviarCorreo false
:local correoDestino "CAMBIAR_AQUI"

:local enviarSftp false
:local sftpIp "CAMBIAR_AQUI"
:local sftpUser "CAMBIAR_AQUI"
:local sftpClave "CAMBIAR_AQUI"
:local sftpCarpeta "subidas"

:if ($clave = "CAMBIAR_AQUI") do={
    :log error "backup-diario: falta definir la clave del backup"
    :error "clave sin definir"
}

:if ([:len [/system script job find where script="backup-diario"]] > 1) do={
    :log warning "backup-diario: ya hay una ejecucion en curso, se omite"
    :error "ejecucion duplicada"
}

/system backup save name=$nombre password=$clave encryption=aes-sha256
/export file=$nombre

:delay 5s
:local espera 0
:while (([:len [/file find where name~"in_progress"]] > 0) && ($espera < 120)) do={
    :delay 2s
    :set espera ($espera + 2)
}

:local archBackup ($nombre . ".backup")
:local archRsc ($nombre . ".rsc")

:if (([:len [/file find where name=$archBackup]] = 0) || ([:len [/file find where name=$archRsc]] = 0)) do={
    :log error "backup-diario: no se encontraron los archivos generados"
    :error "archivos no generados"
}

:log info ("backup-diario: OK " . $nombre)

:if ($enviarCorreo) do={
    :do {
        /tool e-mail send to=$correoDestino \
            subject=("Backup " . [/system identity get name] . " " . [/system clock get date]) \
            body="Backup automatico. El .backup va cifrado; el .rsc no incluye secretos." \
            file=($archBackup, $archRsc)
        :log info "backup-diario: correo en cola de envio"
    } on-error={ :log error "backup-diario: fallo el envio por correo" }
}

:if ($enviarSftp) do={
    :local fecha [/system clock get date]
    :foreach arch in={$archBackup; $archRsc} do={
        :do {
            /tool fetch upload=yes mode=sftp address=$sftpIp \
                user=$sftpUser password=$sftpClave \
                src-path=$arch dst-path=($sftpCarpeta . "/" . $fecha . "-" . $arch)
            :log info ("backup-diario: SFTP OK " . $arch)
        } on-error={ :log error ("backup-diario: fallo SFTP " . $arch) }
    }
}
}

# ---------- Scheduler: todos los dias a las 03:00 ----------
/system scheduler add name=sched-backup-diario \
    start-time=03:00:00 interval=1d \
    policy=ftp,read,write,policy,test,sensitive \
    on-event="/system script run backup-diario" \
    comment="Modulo 02 - ejecuta backup-diario 03:00"

:log info "Modulo 02 importado: backup-diario + sched-backup-diario"

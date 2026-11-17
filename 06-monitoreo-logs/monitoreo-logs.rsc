# =====================================================================
# Modulo 06 - Monitoreo y logs
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: pendiente de probar en laboratorio
# Requisito: modulos 01, 04 y 05 aplicados
#
# Que hace:
#   1. Envia los logs a un servidor syslog (Ubuntu) en la VLAN admin
#   2. Elige que temas se envian (sistema, logins, firewall, errores)
#   3. Activa el log en los drops finales y en las detecciones del modulo 05
#   4. Netwatch: vigila internet, el gateway de la WAN y el servidor syslog
#
# Uso:
#   - Reemplaza CAMBIAR_AQUI con la IP del servidor syslog (VLAN 10).
#   - En el Ubuntu aplica primero rsyslog-mikrotik.conf (ver README).
#   - /import file-name=monitoreo-logs.rsc
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local syslogIp "CAMBIAR_AQUI"
:local routerIp "192.168.10.1"
:local hostInternet "1.1.1.1"

:if ($syslogIp = "CAMBIAR_AQUI") do={
    :error "Define la IP del servidor syslog (variable syslogIp)."
}

# ---------------- 1. Accion remota (syslog) ----------------
# remote-log-format=syslog = BSD syslog (RFC 3164): fecha, identity y mensaje.
# src-address fija = el servidor siempre ve los logs desde la IP de admin.
/system logging action
add name=syslog-ubuntu target=remote remote=$syslogIp remote-port=514 \
    remote-log-format=syslog src-address=$routerIp syslog-facility=local0

# ---------------- 2. Que se envia ----------------
# info ya incluye la mayoria de eventos; account = logins y fallos de login.
/system logging
add topics=info action=syslog-ubuntu
add topics=warning action=syslog-ubuntu
add topics=error action=syslog-ubuntu
add topics=critical action=syslog-ubuntu
add topics=account action=syslog-ubuntu
add topics=firewall action=syslog-ubuntu

# El log del firewall no se guarda en RAM (se llenaria): solo va al servidor.
:foreach r in=[/system logging find where action=memory] do={
    :local t [/system logging get $r topics]
    :if ([:len $t] = 1 && [:typeof [:find $t "info"]] = "num") do={
        /system logging set $r topics=info,!firewall
    }
}

# ---------------- 3. Log en el firewall ----------------
# Prefijos cortos y sin espacios: faciles de filtrar en el servidor.
/ip firewall filter
set [find chain=input action=drop comment~"drop todo lo demas"] log=yes log-prefix="FW-IN-DROP"
set [find chain=forward action=drop comment~"drop todo lo demas"] log=yes log-prefix="FW-FWD-DROP"
set [find comment~"detectar port scan"] log=yes log-prefix="PORTSCAN"
set [find comment~"bloquear 1 dia"] log=yes log-prefix="SSH-BRUTEFORCE"

# ---------------- 4. Netwatch ----------------
# Avisa en el log (y por tanto en el syslog) cuando algo cae o vuelve.
:local gwWan [/ip dhcp-client get ([/ip dhcp-client find]->0) gateway]
:if ([:len $gwWan] = 0) do={
    :error "La WAN no tiene gateway (DHCP client sin IP). Revisa la conexion."
}

/tool netwatch
add host=$hostInternet type=icmp interval=30s timeout=2s comment="Internet" \
    down-script=":log warning \"NETWATCH: internet CAIDO\"" \
    up-script=":log warning \"NETWATCH: internet OK\""
add host=$gwWan type=icmp interval=30s timeout=2s comment="Gateway WAN" \
    down-script=":log warning \"NETWATCH: gateway WAN CAIDO\"" \
    up-script=":log warning \"NETWATCH: gateway WAN OK\""
add host=$syslogIp type=icmp interval=1m timeout=2s comment="Servidor syslog" \
    down-script=":log error \"NETWATCH: servidor syslog CAIDO, los logs se pierden\"" \
    up-script=":log warning \"NETWATCH: servidor syslog OK\""

:log warning "Modulo 06 aplicado: syslog remoto hacia $syslogIp"

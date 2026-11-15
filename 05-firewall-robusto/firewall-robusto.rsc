# =====================================================================
# Modulo 05 - Firewall robusto
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: pendiente de probar en laboratorio
# Requisito: modulos 01 y 04 aplicados (03 opcional)
#
# Que hace:
#   1. Address-lists: BOGONS, REDES-LOCALES y listas dinamicas de bloqueo
#   2. Raw (antes de connection tracking): descarta bloqueados, escaneos,
#      bogons desde la WAN, flags TCP imposibles y spoofing desde la LAN
#   3. Input: deteccion de port scan (PSD) y de fuerza bruta a SSH
#   4. Limita ICMP hacia el router
#   5. Ajustes del kernel: TCP SYN cookies y rp-filter
#   6. Apaga IPv6 y servicios que no se usan
#
# Uso:
#   - Revisa la variable redWanLab (ver nota abajo).
#   - /import file-name=firewall-robusto.rsc
#
# LABORATORIO: la WAN del lab esta en una red privada (192.168.100.0/24),
# que es un "bogon". Sin la excepcion redWanLab, el router descartaria
# el DHCP y todo el trafico del router de la casa. Con IP publica real,
# deja redWanLab vacia ("").
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local redWanLab "192.168.100.0/24"
:local redesLocales {"192.168.10.0/24";"192.168.20.0/24";"192.168.30.0/24";"192.168.40.0/24";"10.99.0.0/24"}

# ---------------- Comprobaciones previas ----------------
:local reglaIcmp [/ip firewall filter find where chain=input protocol=icmp action=accept]
:if ([:len $reglaIcmp] = 0) do={
    :error "No se encontro la regla de ICMP del modulo 01."
}
:if ([:len [/interface list find name=MGMT]] = 0) do={
    :error "No existe la lista MGMT. Aplica primero el modulo 04."
}

# ---------------- 1. Address-lists ----------------
/ip firewall address-list
add list=BOGONS address=0.0.0.0/8 comment="Esta red"
add list=BOGONS address=10.0.0.0/8 comment="RFC1918"
add list=BOGONS address=100.64.0.0/10 comment="CGNAT"
add list=BOGONS address=127.0.0.0/8 comment="Loopback"
add list=BOGONS address=169.254.0.0/16 comment="Link-local"
add list=BOGONS address=172.16.0.0/12 comment="RFC1918"
add list=BOGONS address=192.0.0.0/24 comment="IETF"
add list=BOGONS address=192.0.2.0/24 comment="TEST-NET-1"
add list=BOGONS address=192.168.0.0/16 comment="RFC1918"
add list=BOGONS address=198.18.0.0/15 comment="Benchmark"
add list=BOGONS address=198.51.100.0/24 comment="TEST-NET-2"
add list=BOGONS address=203.0.113.0/24 comment="TEST-NET-3"
add list=BOGONS address=224.0.0.0/4 comment="Multicast"
add list=BOGONS address=240.0.0.0/4 comment="Reservada"

:foreach r in=$redesLocales do={
    /ip firewall address-list add list=REDES-LOCALES address=$r comment="Red interna"
}

# ---------------- 2. Raw (prerouting) ----------------
# Raw actua ANTES del connection tracking: descartar aqui gasta menos CPU.
# El orden importa: primero los bloqueados (tambien los del lab),
# luego la excepcion del lab y despues los bogons.
/ip firewall raw
add chain=prerouting action=drop src-address-list=BLOQUEADOS comment="Raw: drop bloqueados"
add chain=prerouting action=drop src-address-list=PORT-SCANNERS comment="Raw: drop escaneadores"
:if ([:len $redWanLab] > 0) do={
    /ip firewall raw add chain=prerouting action=accept in-interface-list=WAN src-address=$redWanLab \
        comment="Raw: SOLO LAB - red de la casa en la WAN"
}
/ip firewall raw
add chain=prerouting action=drop in-interface-list=WAN src-address-list=BOGONS \
    comment="Raw: drop bogons desde WAN"
add chain=prerouting action=drop protocol=tcp tcp-flags=!fin,!syn,!rst,!ack \
    comment="Raw: drop TCP NULL"
add chain=prerouting action=drop protocol=tcp tcp-flags=fin,psh,urg,!syn,!rst,!ack \
    comment="Raw: drop TCP XMAS"
add chain=prerouting action=drop protocol=tcp tcp-flags=fin,syn comment="Raw: drop TCP SYN+FIN"
add chain=prerouting action=drop protocol=tcp tcp-flags=syn,rst comment="Raw: drop TCP SYN+RST"
add chain=prerouting action=accept in-interface-list=LAN src-address=0.0.0.0 protocol=udp dst-port=67 \
    comment="Raw: DHCP discover desde LAN"
add chain=prerouting action=drop in-interface-list=LAN src-address-list=!REDES-LOCALES \
    comment="Raw: anti-spoofing LAN"

# ---------------- 3. Input: escaneos y fuerza bruta ----------------
# Se insertan antes de "permitir ICMP" (despues de established e invalid).
# Las reglas add-src-to-address-list no aceptan ni descartan: marcan la IP
# y el paquete sigue bajando por la cadena.
/ip firewall filter
add chain=input action=add-src-to-address-list protocol=tcp psd=21,3s,3,1 \
    in-interface-list=WAN address-list=PORT-SCANNERS address-list-timeout=1d \
    comment="Input: detectar port scan" place-before=($reglaIcmp->0)
add chain=input action=add-src-to-address-list protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh-etapa3 address-list=BLOQUEADOS address-list-timeout=1d \
    comment="Input: SSH 4o intento en 1 min - bloquear 1 dia" place-before=($reglaIcmp->0)
add chain=input action=add-src-to-address-list protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh-etapa2 address-list=ssh-etapa3 address-list-timeout=1m \
    comment="Input: SSH etapa 3" place-before=($reglaIcmp->0)
add chain=input action=add-src-to-address-list protocol=tcp dst-port=22 connection-state=new \
    src-address-list=ssh-etapa1 address-list=ssh-etapa2 address-list-timeout=1m \
    comment="Input: SSH etapa 2" place-before=($reglaIcmp->0)
add chain=input action=add-src-to-address-list protocol=tcp dst-port=22 connection-state=new \
    address-list=ssh-etapa1 address-list-timeout=1m \
    comment="Input: SSH etapa 1" place-before=($reglaIcmp->0)

# ---------------- 4. ICMP con limite ----------------
# Lo que pase del limite cae en el drop final de input.
set ($reglaIcmp->0) limit=50/5s,10:packet comment="Input: permitir ICMP (limitado)"

# ---------------- 5. Forward: excepciones entre VLANs (opcional) ----------------
# Ejemplo: usuarios hacia IoT (Chromecast, impresora). Descomenta si lo necesitas.
# :local fwdDrop [/ip firewall filter find where chain=forward action=drop comment~"Forward: drop todo lo demas"]
# /ip firewall filter add chain=forward action=accept in-interface=vlan20-usuarios out-interface=vlan40-iot \
#     comment="Forward: usuarios a IoT" place-before=($fwdDrop->0)

# ---------------- 6. Ajustes del kernel ----------------
# rp-filter=loose: descarta origenes imposibles sin romper el failover del modulo 07.
/ip settings set tcp-syncookies=yes rp-filter=loose

# ---------------- 7. Superficie de ataque ----------------
# IPv6: sin direcciones ni firewall IPv6, es mejor apagarlo.
/ipv6 settings set disable-ipv6=yes
/ip proxy set enabled=no
/ip socks set enabled=no
/ip upnp set enabled=no
/tool romon set enabled=no

:log info "Modulo 05 aplicado: raw, bogons, anti-escaneo y anti fuerza bruta"

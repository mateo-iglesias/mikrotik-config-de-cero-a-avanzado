# =====================================================================
# Modulo 07 - Extras: Servidor PPPoE (como un ISP pequeno)
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: pendiente de probar en laboratorio
# Requisito: modulos 01 y 04 aplicados (05 recomendado)
#
# Que hace:
#   1. Crea la VLAN 50 (pppoe) y la lleva por el trunk ether4
#   2. Pool 10.50.0.10-250 para los clientes; el router es 10.50.0.1
#   3. Perfil: velocidad por cliente, DNS, MSS y lista LAN dinamica
#   4. Servidor PPPoE con autenticacion MSCHAPv2 y una sesion por equipo
#   5. Un cliente (secret) de ejemplo
#
# Uso:
#   - Reemplaza los valores CAMBIAR_AQUI.
#   - /import file-name=pppoe-server.rsc
#   - Cliente de prueba: Ubuntu en ether4 con una subinterfaz VLAN 50.
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local usuario "CAMBIAR_AQUI"
:local clave "CAMBIAR_AQUI"
# Velocidad por cliente: subida/bajada
:local velocidad "10M/30M"

# ---------------- 1. VLAN 50 por el trunk ----------------
/interface vlan
add name=vlan50-pppoe vlan-id=50 interface=bridge-lan comment="VLAN PPPoE"

/interface bridge vlan
add bridge=bridge-lan vlan-ids=50 tagged=bridge-lan,ether4 comment="pppoe"

# ---------------- 2. Pool de clientes ----------------
/ip pool
add name=pool-pppoe ranges=10.50.0.10-10.50.0.250

# Red interna para el anti-spoofing del modulo 05
:if ([:len [/ip firewall address-list find list=REDES-LOCALES]] > 0) do={
    /ip firewall address-list add list=REDES-LOCALES address=10.50.0.0/24 comment="Clientes PPPoE"
}

# ---------------- 3. Perfil ----------------
# interface-list=LAN: cada sesion entra a la lista LAN, asi aplican las
# reglas existentes (DNS al router, internet si, otras VLANs no).
/ppp profile
add name=perfil-pppoe local-address=10.50.0.1 remote-address=pool-pppoe \
    dns-server=10.50.0.1 rate-limit=$velocidad only-one=yes \
    change-tcp-mss=yes interface-list=LAN comment="Clientes PPPoE"

# ---------------- 4. Servidor ----------------
/interface pppoe-server server
add service-name=lab-pppoe interface=vlan50-pppoe default-profile=perfil-pppoe \
    authentication=mschap2 one-session-per-host=yes \
    max-mtu=1480 max-mru=1480 keepalive-timeout=30 disabled=no

# ---------------- 5. Cliente de ejemplo ----------------
/ppp secret
add name=$usuario password=$clave service=pppoe profile=perfil-pppoe \
    comment="Cliente de prueba"

:log info "Modulo 07 - servidor PPPoE activo en vlan50-pppoe"

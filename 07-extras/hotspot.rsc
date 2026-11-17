# =====================================================================
# Modulo 07 - Extras: Hotspot (portal cautivo) en la VLAN de invitados
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: pendiente de probar en laboratorio
# Requisito: modulos 01 y 04 aplicados (VLAN 30 invitados)
#
# Que hace:
#   1. Crea un servidor hotspot en vlan30-invitados
#   2. Login con usuario y contrasena (http-chap)
#   3. Perfil de usuario: 1 dispositivo por usuario, velocidad, tiempo
#      de sesion e inactividad
#   4. Crea un usuario de ejemplo
#
# Uso:
#   - Reemplaza los valores CAMBIAR_AQUI.
#   - /import file-name=hotspot.rsc
#
# Nota: el hotspot crea reglas dinamicas de firewall y NAT (prefijo hs-).
# No las borres: se gestionan solas.
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local hsInterfaz "vlan30-invitados"
:local hsIp "192.168.30.1"
# Nombre de la pagina de login. Usa un dominio que no exista en internet.
:local hsDns "login.invitados.lan"
:local usuario "CAMBIAR_AQUI"
:local clave "CAMBIAR_AQUI"

:if ([:len [/interface find name=$hsInterfaz]] = 0) do={
    :error "No existe $hsInterfaz. Aplica primero el modulo 04."
}

# ---------------- 1. Perfil del servidor ----------------
/ip hotspot profile
add name=hs-invitados hotspot-address=$hsIp dns-name=$hsDns \
    html-directory=hotspot login-by=http-chap use-radius=no

# ---------------- 2. Perfil de usuario ----------------
# rate-limit = subida/bajada del cliente
/ip hotspot user profile
add name=up-invitados shared-users=1 rate-limit="2M/5M" \
    session-timeout=4h idle-timeout=15m keepalive-timeout=2m

# ---------------- 3. Servidor hotspot ----------------
# address-pool=none: las IPs las entrega el DHCP del modulo 04.
/ip hotspot
add name=hotspot-invitados interface=$hsInterfaz profile=hs-invitados \
    address-pool=none addresses-per-mac=1 disabled=no

# Paginas de login por defecto (si la carpeta "hotspot" no existe en Files)
/ip hotspot reset-html hotspot-invitados

# ---------------- 4. Usuario de ejemplo ----------------
/ip hotspot user
add name=$usuario password=$clave profile=up-invitados server=hotspot-invitados \
    comment="Usuario invitado"

:log info "Modulo 07 - hotspot activo en $hsInterfaz"

# =====================================================================
# Modulo 03 - Acceso remoto con WireGuard
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Requisito: configuracion del modulo 01 aplicada y IP publica en la WAN
#
# Que hace:
#   1. Crea la interfaz WireGuard "wg-remoto" (servidor, UDP 13231)
#   2. Asigna la IP del tunel 10.99.0.1/24
#   3. Crea la lista de interfaces VPN
#   4. Firewall: abre UDP 13231 desde WAN y permite Winbox/SSH desde VPN
#   5. Permite la red del tunel en IP Services y en el usuario
#   6. Registra un cliente (peer)
#
# Uso:
#   - Reemplaza TODOS los valores CAMBIAR_AQUI.
#   - /import file-name=acceso-remoto.rsc
#   - Despues: /interface wireguard print  -> copia la public-key del
#     router para la configuracion del cliente.
#
# Nota: el router genera su propia clave privada. Si aplicas el script
# despues de un reset, la clave cambia y hay que actualizar los clientes.
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local wgPuerto 13231
:local wgRedTunel "10.99.0.0/24"
:local redLan "192.168.10.0/24"
:local usuarioAdmin "CAMBIAR_AQUI"
:local clienteNombre "ubuntu-portatil"
:local clienteClavePublica "CAMBIAR_AQUI"
:local clienteIp "10.99.0.2/32"

# ---------------- 1. Interfaz WireGuard ----------------
/interface wireguard add name=wg-remoto listen-port=$wgPuerto mtu=1420 comment="WG servidor acceso remoto"

# ---------------- 2. IP del tunel ----------------
/ip address add address=10.99.0.1/24 interface=wg-remoto comment="WG servidor"

# ---------------- 3. Lista de interfaces VPN ----------------
/interface list add name=VPN comment="Tunel WireGuard"
/interface list member add list=VPN interface=wg-remoto

# ---------------- 4. Firewall (input) ----------------
# Las reglas nuevas van ANTES de "permitir desde LAN" (y del drop final).
:local antes [/ip firewall filter find where chain=input comment="permitir desde LAN"]
:if ([:len $antes] = 0) do={
    :error "No se encontro la regla 'permitir desde LAN' del modulo 01. Revisa el firewall."
}
/ip firewall filter add chain=input action=accept protocol=udp dst-port=$wgPuerto in-interface-list=WAN comment="WG desde WAN" place-before=($antes->0)
/ip firewall filter add chain=input action=accept protocol=tcp dst-port=22,8291 in-interface-list=VPN comment="Admin desde VPN" place-before=($antes->0)

# ---------------- 5. Servicios y usuario ----------------
/ip service set winbox address=($redLan . "," . $wgRedTunel)
/ip service set ssh address=($redLan . "," . $wgRedTunel)
/user set [find name=$usuarioAdmin] address=($redLan . "," . $wgRedTunel)

# ---------------- 6. Cliente (peer) ----------------
# Un peer por dispositivo. Para el celular: copia la linea con otro
# nombre, otra clave publica y allowed-address=10.99.0.3/32
/interface wireguard peers add name=$clienteNombre interface=wg-remoto public-key=$clienteClavePublica allowed-address=$clienteIp comment="Cliente acceso remoto"

# ---------------- OPCIONAL: Winbox desde WAN por IP de confianza ----------------
# Solo si siempre administras desde una IP publica FIJA (ej. la oficina).
# Nunca abras 8291 a todo internet. Descomenta y cambia la IP.
#
# /ip firewall address-list add list=ADMIN-REMOTO address=CAMBIAR_AQUI comment="IP publica de confianza"
# /ip firewall filter add chain=input action=accept protocol=tcp dst-port=8291 in-interface-list=WAN src-address-list=ADMIN-REMOTO comment="Winbox desde IP de confianza" place-before=($antes->0)
# /ip service set winbox address=($redLan . "," . $wgRedTunel . ",CAMBIAR_AQUI")
# /user set [find name=$usuarioAdmin] address=($redLan . "," . $wgRedTunel . ",CAMBIAR_AQUI")

:log info "Modulo 03 aplicado: WireGuard wg-remoto listo"

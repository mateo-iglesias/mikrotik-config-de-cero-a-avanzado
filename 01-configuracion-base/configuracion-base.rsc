# ==============================================================================
#  MikroTik de Cero a Avanzado - Modulo 01: Configuracion base + firewall basico
#  Probado en: hAP lite (RB941-2nD) - RouterOS 7.24.6 (long-term)
# ==============================================================================
#
#  ANTES DE USAR:
#   1. Disenado para un router SIN configuracion (reset con "No Default Configuration").
#   2. Busca y reemplaza TODOS los valores "CAMBIAR_AQUI" (usuario, contrasenas, SSID).
#   3. Puertos: ether1 = WAN (internet) | ether2-ether4 + WiFi = LAN.
#   4. Red LAN: 192.168.10.0/24 - Router: 192.168.10.1 - DHCP: .100 a .200
#
#  COMO APLICARLO:
#   Opcion A (recomendada): Files -> subir este archivo -> System -> Reset Configuration
#             -> marcar "No Default Configuration" -> Run After Reset: este archivo.
#   Opcion B: router ya vacio -> New Terminal -> /import file-name=configuracion-base.rsc
#
#  ADVERTENCIA: no lo apliques sobre un router remoto ni en produccion sin revisarlo.
# ==============================================================================

# Esperar a que las interfaces esten listas (necesario con "Run After Reset")
:delay 15s

# ------------------------------------------------------------------------------
# 1. IDENTIDAD
# ------------------------------------------------------------------------------
/system identity
set name=hAP-lite-LAB

# ------------------------------------------------------------------------------
# 2. INTERFACES: comentarios, bridge LAN y listas WAN/LAN
# ------------------------------------------------------------------------------
/interface ethernet
set [ find default-name=ether1 ] comment=WAN
set [ find default-name=ether2 ] comment=LAN
set [ find default-name=ether3 ] comment=LAN
set [ find default-name=ether4 ] comment=LAN

/interface bridge
add name=bridge-lan comment="Red LAN"

/interface bridge port
add bridge=bridge-lan interface=ether2
add bridge=bridge-lan interface=ether3
add bridge=bridge-lan interface=ether4
add bridge=bridge-lan interface=wlan1

/interface list
add name=WAN
add name=LAN

/interface list member
add interface=ether1 list=WAN
add interface=bridge-lan list=LAN

# ------------------------------------------------------------------------------
# 3. WIFI (2.4 GHz, WPA2-AES, sin WPS)
# ------------------------------------------------------------------------------
/interface wireless security-profiles
add name=wifi-lab mode=dynamic-keys authentication-types=wpa2-psk \
    unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    wpa2-pre-shared-key="CAMBIAR_AQUI" supplicant-identity=""

/interface wireless
set [ find default-name=wlan1 ] mode=ap-bridge band=2ghz-b/g/n \
    channel-width=20mhz frequency=auto country=colombia \
    ssid="CAMBIAR_AQUI" security-profile=wifi-lab wps-mode=disabled disabled=no

# ------------------------------------------------------------------------------
# 4. DIRECCIONAMIENTO LAN + DHCP SERVER
# ------------------------------------------------------------------------------
/ip address
add address=192.168.10.1/24 interface=bridge-lan comment="Gateway LAN"

/ip pool
add name=pool-lan ranges=192.168.10.100-192.168.10.200

/ip dhcp-server
add name=dhcp-lan interface=bridge-lan address-pool=pool-lan

/ip dhcp-server network
add address=192.168.10.0/24 gateway=192.168.10.1 dns-server=192.168.10.1

# ------------------------------------------------------------------------------
# 5. WAN (DHCP client) + DNS + NAT
# ------------------------------------------------------------------------------
/ip dhcp-client
add interface=ether1 use-peer-dns=yes add-default-route=yes comment="WAN"

/ip dns
set servers=1.1.1.1,8.8.8.8 allow-remote-requests=yes

/ip firewall nat
add chain=srcnat out-interface-list=WAN action=masquerade comment="NAT LAN a Internet"

# ------------------------------------------------------------------------------
# 6. FIREWALL BASICO
#    input   = trafico hacia el router
#    forward = trafico que atraviesa el router
# ------------------------------------------------------------------------------
/ip firewall filter
# --- INPUT: proteger el router ---
add chain=input action=accept connection-state=established,related,untracked \
    comment="Input: conexiones establecidas"
add chain=input action=drop connection-state=invalid \
    comment="Input: drop invalid"
add chain=input action=accept protocol=icmp \
    comment="Input: permitir ICMP"
add chain=input action=accept in-interface-list=LAN \
    comment="Input: permitir desde LAN"
add chain=input action=drop \
    comment="Input: drop todo lo demas"
# --- FORWARD: proteger la LAN ---
add chain=forward action=accept connection-state=established,related,untracked \
    comment="Forward: conexiones establecidas"
add chain=forward action=drop connection-state=invalid \
    comment="Forward: drop invalid"
add chain=forward action=drop connection-state=new connection-nat-state=!dstnat \
    in-interface-list=WAN comment="Forward: bloquear nuevas desde WAN"

# ------------------------------------------------------------------------------
# 7. HORA (zona horaria + NTP)
# ------------------------------------------------------------------------------
/system clock
set time-zone-autodetect=no time-zone-name=America/Bogota

/system ntp client
set enabled=yes

/system ntp client servers
add address=time.cloudflare.com
add address=pool.ntp.org

# ------------------------------------------------------------------------------
# 8. HARDENING BASICO
# ------------------------------------------------------------------------------
# Servicios: solo Winbox y SSH, y solo desde la LAN
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set www-ssl disabled=yes
set api disabled=yes
set api-ssl disabled=yes
set winbox available-from=192.168.10.0/24
set ssh available-from=192.168.10.0/24

/ip ssh
set strong-crypto=yes

# Acceso por MAC y descubrimiento de vecinos solo en la LAN
/tool mac-server
set allowed-interface-list=LAN
/tool mac-server mac-winbox
set allowed-interface-list=LAN
/ip neighbor discovery-settings
set discover-interface-list=LAN

# Bandwidth Test apagado
/tool bandwidth-server
set enabled=no

# ------------------------------------------------------------------------------
# 9. USUARIO ADMINISTRADOR
#    Primero se crea el usuario nuevo. NO se deshabilita "admin" aqui:
#    hazlo a mano SOLO despues de comprobar que puedes entrar con el nuevo usuario.
# ------------------------------------------------------------------------------
/user
add name="CAMBIAR_AQUI" group=full password="CAMBIAR_AQUI" \
    address=192.168.10.0/24 comment="Administrador"

# Despues de probar el nuevo usuario, ejecuta en New Terminal:
#   /user disable admin

:log info "Modulo 01 - configuracion base aplicada correctamente"

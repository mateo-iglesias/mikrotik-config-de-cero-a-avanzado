# =====================================================================
# Modulo 04 - VLANs y colas
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: bloques de VLANs probados en laboratorio; forward y colas pendientes de probar
# Requisito: configuracion del modulo 01 aplicada (modulo 03 opcional)
#
# Que hace:
#   1. Crea 4 VLANs sobre bridge-lan: 10 admin, 20 usuarios,
#      30 invitados, 40 IoT (IP, pool y DHCP para cada una)
#   2. Crea la lista MGMT (solo admin) y mete las VLANs en la lista LAN
#   3. Firewall input: administracion solo desde MGMT; las demas VLANs
#      solo pueden pedir DNS y DHCP al router
#   4. Puertos: ether2 = admin | ether3 + wlan1 = usuarios |
#      ether4 = trunk 20/30/40 | wlan2-invitados (virtual AP) = invitados
#   5. Mueve 192.168.10.1 y el DHCP de admin a vlan10-admin y activa
#      VLAN filtering (el cambio critico, todo seguido)
#   6. Firewall forward: aislamiento entre VLANs (default deny)
#   7. Colas: simple queues con PCQ por VLAN
#
# Uso:
#   - Conecta tu PC a ether2 ANTES de aplicarlo (sera el unico puerto
#     de administracion).
#   - Haz un backup antes (modulo 02).
#   - Reemplaza los valores CAMBIAR_AQUI y ajusta las velocidades.
#   - /import file-name=vlans-colas.rsc
#   - Al terminar: ipconfig /renew (Windows) o reconecta el cable.
#
# Nota: el hAP lite no tiene offload de hardware para bridge VLAN
# filtering. Al activarlo, el CPU conmuta todo (desaparece la bandera H).
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local claveInvitados "CAMBIAR_AQUI"
:local ssidInvitados "LAB-Invitados"
# Velocidad real del internet (mide con un speedtest). Formato RouterOS.
:local bajada "120M"
:local subida "CAMBIAR_AQUI"

# ---------------- Comprobaciones previas ----------------
:if ([:len [/interface bridge find name=bridge-lan]] = 0) do={
    :error "No existe bridge-lan. Aplica primero el modulo 01."
}
:local reglaLan [/ip firewall filter find where chain=input comment~"permitir desde LAN"]
:local reglaDrop [/ip firewall filter find where chain=input action=drop comment~"drop todo lo demas"]
:if ([:len $reglaLan] = 0 || [:len $reglaDrop] = 0) do={
    :error "No se encontraron las reglas 'permitir desde LAN' o 'drop todo lo demas' del modulo 01."
}
:if ($subida = "CAMBIAR_AQUI") do={
    :error "Define la variable subida (ej. 30M) antes de importar."
}

# ---------------- 1. Interfaces VLAN ----------------
/interface vlan
add name=vlan10-admin vlan-id=10 interface=bridge-lan comment="VLAN admin"
add name=vlan20-usuarios vlan-id=20 interface=bridge-lan comment="VLAN usuarios"
add name=vlan30-invitados vlan-id=30 interface=bridge-lan comment="VLAN invitados"
add name=vlan40-iot vlan-id=40 interface=bridge-lan comment="VLAN IoT"

# ---------------- 2. IP, pools y DHCP (20, 30, 40) ----------------
# La VLAN 10 reutiliza 192.168.10.1 y el DHCP del modulo 01 (paso 7).
/ip address
add address=192.168.20.1/24 interface=vlan20-usuarios comment="Gateway usuarios"
add address=192.168.30.1/24 interface=vlan30-invitados comment="Gateway invitados"
add address=192.168.40.1/24 interface=vlan40-iot comment="Gateway IoT"

/ip pool
add name=pool-usuarios ranges=192.168.20.100-192.168.20.200
add name=pool-invitados ranges=192.168.30.100-192.168.30.200
add name=pool-iot ranges=192.168.40.100-192.168.40.200

/ip dhcp-server
add name=dhcp-usuarios interface=vlan20-usuarios address-pool=pool-usuarios lease-time=1d
add name=dhcp-invitados interface=vlan30-invitados address-pool=pool-invitados lease-time=1h
add name=dhcp-iot interface=vlan40-iot address-pool=pool-iot lease-time=1d

/ip dhcp-server network
add address=192.168.20.0/24 gateway=192.168.20.1 dns-server=192.168.20.1 comment="Usuarios"
add address=192.168.30.0/24 gateway=192.168.30.1 dns-server=192.168.30.1 comment="Invitados"
add address=192.168.40.0/24 gateway=192.168.40.1 dns-server=192.168.40.1 comment="IoT"

# ---------------- 3. Listas de interfaces ----------------
# bridge-lan queda temporalmente en MGMT para no cortar el acceso;
# se retira en el paso 8, despues del cambio critico.
/interface list
add name=MGMT comment="Administracion del router"

/interface list member
add list=LAN interface=vlan10-admin
add list=LAN interface=vlan20-usuarios
add list=LAN interface=vlan30-invitados
add list=LAN interface=vlan40-iot
add list=MGMT interface=vlan10-admin
add list=MGMT interface=bridge-lan comment="temporal"

# ---------------- 4. Firewall input ----------------
/ip firewall filter
set ($reglaLan->0) in-interface-list=MGMT comment="Input: admin desde MGMT"
add chain=input action=accept protocol=udp dst-port=53,67 in-interface-list=LAN \
    comment="Input: DNS y DHCP desde LAN" place-before=($reglaDrop->0)
add chain=input action=accept protocol=tcp dst-port=53 in-interface-list=LAN \
    comment="Input: DNS TCP desde LAN" place-before=($reglaDrop->0)

# Acceso por MAC y descubrimiento de vecinos solo en MGMT
/tool mac-server set allowed-interface-list=MGMT
/tool mac-server mac-winbox set allowed-interface-list=MGMT
/ip neighbor discovery-settings set discover-interface-list=MGMT

# ---------------- 5. WiFi de invitados (virtual AP) ----------------
/interface wireless security-profiles
add name=wifi-invitados mode=dynamic-keys authentication-types=wpa2-psk \
    unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    wpa2-pre-shared-key=$claveInvitados supplicant-identity=""

/interface wireless
add name=wlan2-invitados master-interface=wlan1 mode=ap-bridge \
    ssid=$ssidInvitados security-profile=wifi-invitados \
    default-forwarding=no wps-mode=disabled disabled=no

# ---------------- 6. Puertos del bridge y tabla VLAN ----------------
# Mientras vlan-filtering=no, nada de esto tiene efecto.
/interface bridge port
add bridge=bridge-lan interface=wlan2-invitados pvid=30 \
    frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
set [find interface=ether2] pvid=10 frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
set [find interface=ether3] pvid=20 frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
set [find interface=wlan1] pvid=20 frame-types=admit-only-untagged-and-priority-tagged ingress-filtering=yes
set [find interface=ether4] frame-types=admit-only-vlan-tagged ingress-filtering=yes

/interface bridge vlan
add bridge=bridge-lan vlan-ids=10 tagged=bridge-lan untagged=ether2 comment="admin"
add bridge=bridge-lan vlan-ids=20 tagged=bridge-lan,ether4 untagged=ether3,wlan1 comment="usuarios"
add bridge=bridge-lan vlan-ids=30 tagged=bridge-lan,ether4 untagged=wlan2-invitados comment="invitados"
add bridge=bridge-lan vlan-ids=40 tagged=bridge-lan,ether4 comment="IoT"

# ---------------- 7. CAMBIO CRITICO ----------------
# Los tres cambios van seguidos: por separado, cada uno corta el acceso.
/ip address set [find address="192.168.10.1/24"] interface=vlan10-admin
/ip dhcp-server set [find interface=bridge-lan] interface=vlan10-admin
/interface bridge set [find name=bridge-lan] vlan-filtering=yes \
    frame-types=admit-only-vlan-tagged ingress-filtering=yes

# ---------------- 8. Limpieza ----------------
/interface list member remove [find list=MGMT interface=bridge-lan]
/interface list member remove [find list=LAN interface=bridge-lan]

# ---------------- 9. Firewall forward: aislamiento entre VLANs ----------------
# Se agregan al final de forward (despues de "bloquear nuevas desde WAN").
/ip firewall filter
add chain=forward action=accept in-interface-list=MGMT comment="Forward: admin a todo"
add chain=forward action=accept in-interface-list=LAN out-interface-list=WAN \
    comment="Forward: LAN a internet"
add chain=forward action=drop comment="Forward: drop todo lo demas"

# ---------------- 10. Colas (simple queues + PCQ) ----------------
# Sin FastTrack (modulo 01): el trafico fasttrackeado se salta las colas.
# Orden de max-limit en simple queues: subida/bajada.
:local wanIf [/interface list member get ([/interface list member find list=WAN]->0) interface]

/queue simple
add name=total target=192.168.10.0/24,192.168.20.0/24,192.168.30.0/24,192.168.40.0/24 \
    dst=$wanIf max-limit=($subida . "/" . $bajada) comment="Total internet"
add name=admin parent=total target=192.168.10.0/24 dst=$wanIf priority=1/1 \
    limit-at=2M/10M max-limit=($subida . "/" . $bajada) comment="Admin: prioridad maxima"
add name=usuarios parent=total target=192.168.20.0/24 dst=$wanIf priority=4/4 \
    queue=pcq-upload-default/pcq-download-default \
    limit-at=5M/40M max-limit=($subida . "/" . $bajada) comment="Usuarios: reparto equitativo"
add name=iot parent=total target=192.168.40.0/24 dst=$wanIf priority=6/6 \
    queue=pcq-upload-default/pcq-download-default \
    limit-at=1M/2M max-limit=2M/5M comment="IoT: limitado"
add name=invitados parent=total target=192.168.30.0/24 dst=$wanIf priority=8/8 \
    queue=pcq-upload-default/pcq-download-default \
    limit-at=1M/5M max-limit=5M/20M comment="Invitados: limitado"

:log info "Modulo 04 aplicado: VLANs 10/20/30/40, aislamiento y colas"

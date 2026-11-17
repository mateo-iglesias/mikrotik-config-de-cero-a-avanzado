# =====================================================================
# Modulo 07 - Extras: Dos internets con failover y balanceo PCC
# Repositorio: mikrotik-de-cero-a-avanzado
# Equipo: MikroTik hAP lite (RB941-2nD) - RouterOS 7.24.6 long-term
# Estado: pendiente de probar en laboratorio
# Requisito: modulos 01, 04 y 05 aplicados (05 deja rp-filter=loose)
#
# Que hace:
#   1. Saca ether3 del bridge y lo convierte en WAN2 (DHCP client)
#   2. Crea las tablas de ruteo to-wan1 y to-wan2
#   3. Script "pcc-rutas": crea rutas recursivas con check-gateway hacia
#      una IP de sonda por cada WAN (failover real, no solo "cable caido")
#   4. Mangle PCC: reparte las conexiones nuevas entre las dos WAN y
#      mantiene cada conexion siempre por la misma WAN
#
# Uso:
#   - WAN2 debe estar en una red DISTINTA a WAN1 (otro proveedor, o el
#     celular a traves de un router de viaje en modo cliente).
#   - Haz backup. Aplicalo desde un PC en ether2 (ether3 deja la LAN).
#   - /import file-name=failover-pcc.rsc
#
# ADVERTENCIA: modifica el DHCP client de la WAN principal. Si algo
# falla, el router se queda sin ruta por defecto (sin internet), pero
# conservas el acceso local por ether2.
# =====================================================================

:delay 15s

# ---------------- Variables ----------------
:local wan1 "ether1"
:local wan2 "ether3"
# IPs de sonda: una por WAN. No uses los DNS del router (1.1.1.1, 8.8.8.8).
:local sonda1 "1.0.0.1"
:local sonda2 "9.9.9.9"

:if ([:len [/ip firewall address-list find list=REDES-LOCALES]] = 0) do={
    :error "Falta la address-list REDES-LOCALES. Aplica primero el modulo 05."
}

# ---------------- 1. ether3 pasa a ser WAN2 ----------------
/interface bridge vlan set [find vlan-ids=20] untagged=wlan1
/interface bridge port remove [find interface=$wan2]
/interface ethernet set [find default-name=$wan2] comment=WAN2
/interface list member add list=WAN interface=$wan2

# ---------------- 2. Tablas de ruteo ----------------
/routing table
add name=to-wan1 fib comment="Salida por WAN1"
add name=to-wan2 fib comment="Salida por WAN2"

# ---------------- 3. Script de rutas ----------------
# Se ejecuta cada vez que un DHCP client obtiene o pierde la IP.
# Version legible del script (con los valores por defecto):
#   :local wans {"ether1";"ether3"}
#   :local sondas {"1.0.0.1";"9.9.9.9"}
#   :for i from=0 to=1 do={
#       :local n ($i + 1)
#       :local otra (2 - $i)
#       :local wan ($wans->$i)
#       :local sonda ($sondas->$i)
#       :local tag ("PCC-WAN" . $n)
#       /ip route remove [find comment~$tag]
#       :local c [/ip dhcp-client find interface=$wan]
#       :if ([:len $c] > 0) do={
#           :local gw [/ip dhcp-client get ($c->0) gateway]
#           :local st [/ip dhcp-client get ($c->0) status]
#           :if ($st = "bound" && [:len $gw] > 0) do={
#               /ip route add dst-address=($sonda . "/32") gateway=$gw scope=10 comment=($tag . " sonda")
#               /ip route add dst-address=0.0.0.0/0 gateway=$sonda target-scope=11 check-gateway=ping distance=$n comment=($tag . " main")
#               /ip route add dst-address=0.0.0.0/0 gateway=($sonda . "@main") target-scope=11 check-gateway=ping distance=1 routing-table=("to-wan" . $n) comment=($tag . " tabla")
#               /ip route add dst-address=0.0.0.0/0 gateway=($sonda . "@main") target-scope=11 check-gateway=ping distance=2 routing-table=("to-wan" . $otra) comment=($tag . " respaldo")
#           }
#       }
#   }
/system script
add name=pcc-rutas policy=read,write,policy,test source=(":local wans {\"" . $wan1 . "\";\"" . $wan2 . "\"}\n:local sondas {\"" . $sonda1 . "\";\"" . $sonda2 . "\"}\n:for i from=0 to=1 do={\n    :local n (\$i + 1)\n    :local otra (2 - \$i)\n    :local wan (\$wans->\$i)\n    :local sonda (\$sondas->\$i)\n    :local tag (\"PCC-WAN\" . \$n)\n    /ip route remove [find comment~\$tag]\n    :local c [/ip dhcp-client find interface=\$wan]\n    :if ([:len \$c] > 0) do={\n        :local gw [/ip dhcp-client get (\$c->0) gateway]\n        :local st [/ip dhcp-client get (\$c->0) status]\n        :if (\$st = \"bound\" && [:len \$gw] > 0) do={\n            /ip route add dst-address=(\$sonda . \"/32\") gateway=\$gw scope=10 comment=(\$tag . \" sonda\")\n            /ip route add dst-address=0.0.0.0/0 gateway=\$sonda target-scope=11 check-gateway=ping distance=\$n comment=(\$tag . \" main\")\n            /ip route add dst-address=0.0.0.0/0 gateway=(\$sonda . \"@main\") target-scope=11 check-gateway=ping distance=1 routing-table=(\"to-wan\" . \$n) comment=(\$tag . \" tabla\")\n            /ip route add dst-address=0.0.0.0/0 gateway=(\$sonda . \"@main\") target-scope=11 check-gateway=ping distance=2 routing-table=(\"to-wan\" . \$otra) comment=(\$tag . \" respaldo\")\n        }\n    }\n}")

# ---------------- 4. DHCP clients ----------------
# Las rutas por defecto ya no las crea el DHCP: las crea pcc-rutas.
/ip dhcp-client
set [find interface=$wan1] add-default-route=no script="/system script run pcc-rutas"
add interface=$wan2 add-default-route=no use-peer-dns=no \
    script="/system script run pcc-rutas" comment="WAN2"

# ---------------- 5. Mangle PCC ----------------
/ip firewall mangle
# Conexiones que ENTRAN por cada WAN: la respuesta sale por la misma
add chain=prerouting action=mark-connection in-interface=$wan1 connection-mark=no-mark \
    new-connection-mark=wan1-conn passthrough=yes comment="PCC: entra por WAN1"
add chain=prerouting action=mark-connection in-interface=$wan2 connection-mark=no-mark \
    new-connection-mark=wan2-conn passthrough=yes comment="PCC: entra por WAN2"
# Conexiones nuevas desde la LAN hacia internet: reparto 50/50
# both-addresses = mismo origen y destino siempre por la misma WAN
add chain=prerouting action=mark-connection in-interface-list=LAN connection-mark=no-mark \
    dst-address-type=!local dst-address-list=!REDES-LOCALES \
    per-connection-classifier=both-addresses:2/0 \
    new-connection-mark=wan1-conn passthrough=yes comment="PCC: reparto a WAN1"
add chain=prerouting action=mark-connection in-interface-list=LAN connection-mark=no-mark \
    dst-address-type=!local dst-address-list=!REDES-LOCALES \
    per-connection-classifier=both-addresses:2/1 \
    new-connection-mark=wan2-conn passthrough=yes comment="PCC: reparto a WAN2"
# Marca de ruteo segun la marca de conexion
add chain=prerouting action=mark-routing in-interface-list=LAN connection-mark=wan1-conn \
    dst-address-list=!REDES-LOCALES new-routing-mark=to-wan1 passthrough=no \
    comment="PCC: rutear por WAN1"
add chain=prerouting action=mark-routing in-interface-list=LAN connection-mark=wan2-conn \
    dst-address-list=!REDES-LOCALES new-routing-mark=to-wan2 passthrough=no \
    comment="PCC: rutear por WAN2"
# Trafico del propio router (ej. respuestas de WireGuard)
add chain=output action=mark-routing connection-mark=wan1-conn \
    new-routing-mark=to-wan1 passthrough=no comment="PCC: router por WAN1"
add chain=output action=mark-routing connection-mark=wan2-conn \
    new-routing-mark=to-wan2 passthrough=no comment="PCC: router por WAN2"

# ---------------- 6. Crear las rutas ahora ----------------
/system script run pcc-rutas

:log warning "Modulo 07 - failover y PCC activos ($wan1 + $wan2)"

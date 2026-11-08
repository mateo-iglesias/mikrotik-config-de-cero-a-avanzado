# Módulo 01 — Preparación + configuración base + firewall básico

Al terminar este módulo tendrás un MikroTik con **RouterOS v7**, internet funcionando, WiFi seguro, DHCP para tus equipos, un **firewall básico** y los servicios innecesarios apagados.

> ⚡ **¿Con afán?** Ve directo a [Aplicar el script](#-aplicar-el-script).

---

## 🗺️ Diseño de la red

| Elemento | Valor |
|---|---|
| WAN | `ether1` — recibe internet por DHCP |
| LAN | `ether2`, `ether3`, `ether4` y `wlan1` unidos en `bridge-lan` |
| Red LAN | `192.168.10.0/24` |
| Router (gateway) | `192.168.10.1` |
| Rango DHCP | `192.168.10.100` – `192.168.10.200` (de `.2` a `.99` quedan libres para IPs fijas) |

```
          INTERNET
             │
       ether1 (WAN)
             │
   [ hAP lite: NAT + firewall ]
             │
       bridge-lan 192.168.10.1
    ┌──────┬──┴───┬──────┐
 ether2 ether3 ether4  wlan1
```

> No usamos `192.168.88.x` (la de fábrica de MikroTik) ni `192.168.100.x` (común en routers de ISP) para evitar choques de red.

---

## Parte 1 — Preparación

### 1.1 Reset sin configuración
**System → Reset Configuration** → ✅ **No Default Configuration** → **Reset Configuration**.
Arrancamos con el router vacío para entender cada cosa que se configura.

### 1.2 Conectarse por MAC
PC en `ether2` → Winbox → **Neighbors** → clic en la **MAC** → usuario `admin`, sin contraseña.
Sin configuración el router no tiene IP, pero Winbox lo encuentra en capa 2.

### 1.3 Actualizar a RouterOS v7
MikroTik obliga a este orden:

1. Dar internet temporal: **IP → DHCP Client** en `ether1` + **IP → DNS** (`8.8.8.8`).
2. **System → Packages → Check For Updates** → canal `long-term` → última **v6** → Download & Install.
3. Mismo menú → canal `upgrade` → **v7** → Download & Install.
4. **System → RouterBOARD → Upgrade** → **System → Reboot** (actualiza el firmware, el "BIOS" del equipo).

> ⚠️ Nunca cortes la corriente durante una actualización.

### 1.4 Si sale "not enough disk space" → Netinstall
El hAP lite solo tiene 16 MB y muchas veces no le alcanza para saltar a v7. La solución es **Netinstall**, que formatea e instala limpio por cable.

**Desde Linux** (descarga de [mikrotik.com/download](https://mikrotik.com/download) el `netinstall` para Linux y los paquetes **SMIPS** `routeros` y `wireless`):
```bash
# PC conectado por cable directo a ether1
sudo ip addr add 192.168.88.2/24 dev <tu-interfaz>
sudo ufw disable    # si está activo; bloquea BOOTP/TFTP
sudo ./netinstall-cli -e -v -i <tu-interfaz> routeros-7.X-smips.npk wireless-7.X-smips.npk
```
- `-e` instala **sin configuración por defecto**.
- Pon el router en modo Netinstall: desconecta la corriente → **mantén presionado reset** → conecta la corriente → suelta cuando Netinstall lo detecte (~20 s).
- Espera `Successfully finished installing device`. Después: `sudo ip addr del ...` y `sudo ufw enable`.

> 📌 En v7 el WiFi es un paquete aparte (`wireless`). Si no lo instalas, no hay WiFi.

---

## Parte 2 — Configuración paso a paso en Winbox

### 2.1 Identidad
**System → Identity** → `hAP-lite-LAB`.
Sirve para saber en qué equipo estás cuando administras varios.

### 2.2 Bridge LAN
Por defecto, cada puerto de un router es una red separada. El **bridge** los une como si fuera un switch.

1. **Interfaces** → comentar `ether1` = `WAN` y `ether2-4` = `LAN`.
2. **Bridge → [+]** → Name: `bridge-lan`.
3. **Bridge → Ports → [+]** → agregar `ether2`, `ether3`, `ether4` y `wlan1`.
4. **IP → Addresses → [+]** → `192.168.10.1/24` en `bridge-lan`.

> `ether1` **no** va en el bridge: es la conexión hacia afuera, y separarla es lo que permite hacer NAT y firewall.

### 2.3 WAN, DNS y NAT
1. **IP → DHCP Client → [+]** → Interface `ether1`, Use Peer DNS ✅, Add Default Route `yes`.
2. **IP → DNS** → Servers `1.1.1.1`, `8.8.8.8` · Allow Remote Requests ✅ (el router será el DNS de la LAN).
3. **IP → Firewall → NAT → [+]** → Chain `srcnat`, Out. Interface List `WAN`, Action `masquerade`.

> **NAT masquerade:** cambia la IP privada de tus equipos por la IP de la WAN al salir a internet.
> ⚠️ **Allow Remote Requests** convierte al router en un *open resolver* si no hay firewall. La regla de input del paso 2.7 lo protege.

### 2.4 DHCP server
**IP → DHCP Server → DHCP Setup**: interfaz `bridge-lan`, gateway `192.168.10.1`, rango `192.168.10.100-192.168.10.200`, DNS `192.168.10.1`.

### 2.5 WiFi
1. **Wireless → Security Profiles → [+]** → `wifi-lab`, solo **WPA2 PSK**, cifrado solo **aes ccm**, contraseña de 12+ caracteres.
2. **Wireless → wlan1** → Mode `ap bridge`, Band `2GHz-B/G/N`, Channel Width `20MHz`, Country `colombia`, SSID, Security Profile `wifi-lab`, WPS `disabled`.
3. Habilitar `wlan1` (viene apagada).

> WPA/TKIP son inseguros, y WPS se rompe por fuerza bruta. Este equipo no soporta WPA3.

### 2.6 Hora y usuario
1. **System → Clock** → Time Zone `America/Bogota`.
2. **System → NTP Client** → Enabled, servers `time.cloudflare.com`, `pool.ntp.org`.
3. **System → Users → [+]** → usuario propio (no `admin`), grupo `full`, Allowed Address `192.168.10.0/24`.
4. Probar el nuevo usuario y **solo después** deshabilitar `admin`.

> Sin la hora correcta, los logs no sirven como evidencia y las tareas programadas fallan.

### 2.7 Firewall básico
Primero **Interfaces → Interface List**: lista `WAN` (`ether1`) y lista `LAN` (`bridge-lan`). Luego, en **IP → Firewall → Filter Rules**, en este orden:

| # | Chain | Condición | Acción |
|---|---|---|---|
| 1 | input | established, related, untracked | accept |
| 2 | input | invalid | drop |
| 3 | input | protocol icmp | accept |
| 4 | input | in-interface-list LAN | accept |
| 5 | input | — | **drop** |
| 6 | forward | established, related, untracked | accept |
| 7 | forward | invalid | drop |
| 8 | forward | new + connection-nat-state **!dstnat** + in-interface-list WAN | **drop** |

- **input** = tráfico hacia el router · **forward** = tráfico que pasa a través del router.
- Las reglas se leen de arriba hacia abajo y gana la primera que coincide.
- MikroTik **permite todo por defecto**: sin el drop final, el router queda abierto.

> 💡 Activa **Safe Mode** (`Ctrl+X`) antes de tocar el firewall: si te bloqueas, el router revierte los cambios solo.

### 2.8 Hardening básico
| Dónde | Qué |
|---|---|
| IP → Services | Deshabilitar `telnet`, `ftp`, `www`, `www-ssl`, `api`, `api-ssl`. A `winbox` y `ssh` → Available From `192.168.10.0/24` |
| IP → SSH | Strong Crypto ✅ |
| Tools → MAC Server | MAC Telnet y MAC Winbox → lista `LAN` |
| IP → Neighbors → Discovery Settings | Interface `LAN` |
| Tools → BTest Server | Deshabilitado |

> **Defensa en profundidad:** aunque el firewall falle, los servicios innecesarios ya están apagados.
> Las filas con **D** en IP → Services son dinámicas: las abren otras funciones (DHCP, DNS, NTP) y se protegen con el firewall.

---

## ⚡ Aplicar el script

Archivo: [`configuracion-base.rsc`](./configuracion-base.rsc)

1. Abre el archivo y reemplaza **todos** los `CAMBIAR_AQUI`: usuario, contraseña, SSID y clave WiFi.
2. Winbox → **Files** → arrastra el archivo.
3. **System → Reset Configuration** → ✅ **No Default Configuration** → **Run After Reset**: `configuracion-base.rsc` → Reset.
4. Conéctate a `192.168.10.1` con tu nuevo usuario.
5. Si todo funciona → New Terminal → `/user disable admin`.

> ⚠️ Haz un backup antes y no lo apliques sobre un router remoto: cambia IPs y puedes perder el acceso.

---

## ✅ Verificación

| Prueba | Dónde | Resultado esperado |
|---|---|---|
| Internet del router | New Terminal: `ping google.com` | Responde |
| Ruta por defecto | `/ip route print` | `0.0.0.0/0` vía el gateway de la WAN |
| IP del cliente | PC: `ipconfig` / `ip addr` | `192.168.10.1xx`, gateway y DNS `192.168.10.1` |
| WiFi | Wireless → Registration | Aparecen los equipos conectados |
| Servicios | `/ip service print` | Solo `winbox` y `ssh` activos |
| Firewall | IP → Firewall → Filter Rules | Los contadores de cada regla suben |

---

## 🛠️ Problemas frecuentes

| Problema | Causa | Solución |
|---|---|---|
| `could not resolve DNS name` al actualizar | El router no tiene DNS | IP → DNS → agregar `8.8.8.8` |
| `not enough disk space` al pasar a v7 | El hAP lite solo tiene 16 MB | Usar Netinstall (sección 1.4) |
| Netinstall: `Could not determine architecture` | El router arrancó normal, no en modo Netinstall | Mantener presionado reset más tiempo (~20 s) |
| El PC recibe `169.254.x.x` | No hay DHCP server o el cable está en `ether1` | Crear el DHCP server / cambiar de puerto |
| Los clientes navegan por IP pero no por nombre | El DHCP no entrega DNS | DHCP Server → Networks → DNS `192.168.10.1` |
| Winbox se desconecta al agregar `ether2` al bridge | La conexión pasó al bridge | Normal: reconectar por MAC |

---

## 🔐 Notas de seguridad

- **Una regla mal hecha da una falsa sensación de seguridad.** Por ejemplo, olvidar el `!` en `!dstnat` invierte la regla 8 y deja la LAN expuesta. Siempre verifica el firewall con un escaneo de puertos (por ejemplo, con Nmap) desde fuera de la red.
- `/export` no incluye contraseñas, pero **sí incluye el número de serie**. Bórralo antes de publicar una configuración.
- Al actualizar un router en producción, los reinicios no borran la configuración, pero haz siempre `backup` + `export` antes, sobre todo al pasar de v6 a v7.

---

⬅️ [Volver al inicio](../README.md) · ➡️ Siguiente: Módulo 02 — Backup automático

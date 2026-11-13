# 03 · Acceso remoto 🌐

Administrar el router desde cualquier red (otra ciudad, datos móviles, la oficina) **sin exponer Winbox a internet**, usando una VPN **WireGuard** en la que el propio MikroTik es el servidor.

> **Requisito:** el router necesita **IP pública** en la WAN. Si estás detrás de CGNAT, nadie puede llegar a tu router desde afuera y este módulo no aplica tal cual (necesitarías un VPS intermedio).

---

## 📖 Qué se hace y por qué

### La forma "rápida": Winbox directo a la IP pública
Abrir el puerto 8291 en la WAN y entrar con usuario y contraseña **funciona**, pero deja la puerta de administración a la vista de **todo internet**:

- Bots escanean internet las 24 horas y prueban contraseñas (fuerza bruta).
- Si aparece una falla en Winbox, quedas expuesto. Ya ocurrió: **CVE-2018-14847** permitía leer usuarios y contraseñas sin autenticarse, y miles de routers fueron comprometidos.

### La forma segura: WireGuard
WireGuard es una VPN: crea un **túnel cifrado** entre tu equipo y el router. Winbox sigue funcionando igual (usuario y contraseña), pero **solo dentro del túnel**.

| Paso | Qué haces | Con qué te autenticas |
|---|---|---|
| 1 | Activas el túnel en tu equipo | Claves de WireGuard |
| 2 | Abres Winbox a `10.99.0.1` | Tu usuario y contraseña de siempre |

Hacia internet solo queda abierto **UDP 13231**, y WireGuard **no responde** a quien no tenga una clave válida: para un escáner, el puerto parece cerrado.

### Claves pública y privada
Cada equipo tiene un par de claves:
- **Privada** = la llave. Nunca sale del equipo.
- **Pública** = el candado. Se puede compartir.

El router guarda el candado de cada cliente, y cada cliente guarda el candado del router. En la conexión, cada lado demuestra que tiene la llave correcta **sin enviarla**. Cada dispositivo tiene su propio par: si pierdes el celular, borras solo ese peer.

---

## 🗺️ Diseño

| Elemento | Valor |
|---|---|
| Interfaz | `wg-remoto`, UDP `13231`, MTU `1420` |
| Red del túnel | `10.99.0.0/24` (no debe chocar con ninguna red tuya) |
| Router | `10.99.0.1` |
| Cliente 1 (portátil) | `10.99.0.2/32` |
| Cliente 2 (celular) | `10.99.0.3/32` |
| Lista de interfaces | `VPN` = `wg-remoto` |
| Tipo de túnel | **Split tunnel**: solo el tráfico hacia el router va por la VPN |

Resumen: en el router se configuran **3 cosas** (interfaz, firewall, un peer por dispositivo) y en cada dispositivo **1 cosa** (la app de WireGuard con su archivo de configuración).

---

## 🖱️ Pasos en Winbox

> ⚠️ Activa **Safe Mode** antes de tocar el firewall, los servicios o el usuario.

### 1. Interfaz WireGuard
**WireGuard → pestaña WireGuard → +**
- Name: `wg-remoto`
- Listen Port: `13231`
- MTU: `1420`
- **Apply** → la clave privada se genera sola. Copia la **Public Key**.

### 2. IP del túnel
**IP → Addresses → +**
- Address: `10.99.0.1/24`
- Interface: `wg-remoto`
- Comment: `WG servidor`

### 3. Lista de interfaces VPN
- **Interfaces → pestaña Interface List → Lists → +** → Name: `VPN`
- **Interface List → +** → List: `VPN`, Interface: `wg-remoto`

### 4. Firewall (chain input)
**IP → Firewall → Filter Rules → +**

| Regla | Chain | Protocol | Dst. Port | In. Interface List | Action | Comment |
|---|---|---|---|---|---|---|
| A | input | udp | 13231 | WAN | accept | `WG desde WAN` |
| B | input | tcp | 22,8291 | VPN | accept | `Admin desde VPN` |

Arrastra las dos reglas **antes de "permitir desde LAN" y del drop final**. Las reglas se leen de arriba hacia abajo: si quedan debajo del drop, nunca se aplican.

### 5. Servicios y usuario
El módulo 01 limitó Winbox, SSH y el usuario a la LAN. Hay que **agregar** la red del túnel, sin borrar la LAN:
- **IP → Services →** `winbox` → Available From → **+** `10.99.0.0/24` (igual en `ssh`)
- **System → Users →** tu usuario → Allowed Address → **+** `10.99.0.0/24`

### 6. Generar las claves del cliente (ejemplo con Ubuntu)
```bash
sudo apt install -y wireguard
sudo sh -c 'cd /etc/wireguard && umask 077 && wg genkey | tee cliente.key | wg pubkey > cliente.pub'
sudo cat /etc/wireguard/cliente.pub
```
En Windows y en el celular, la app oficial de WireGuard genera las claves al crear un túnel vacío.

### 7. Registrar el cliente en el router (peer)
**WireGuard → pestaña Peers → +**
- Name: `ubuntu-portatil`
- Interface: `wg-remoto`
- Public Key: la **pública del cliente**
- Allowed Address: `10.99.0.2/32`. Funciona como filtro (este peer solo puede usar esa IP) y como ruta.
- Endpoint: **vacío**. El cliente llega desde cualquier red y el router aprende su dirección.

### 8. Configurar el cliente
Usa la plantilla [`cliente-wireguard.conf`](./cliente-wireguard.conf):
- Linux: `/etc/wireguard/wg-lab.conf` con permisos `600`, y después `sudo wg-quick up wg-lab`.
- Windows o celular: impórtala en la app y activa el túnel.

### 9. Entrar
Con el túnel activo: **Winbox → Connect To: `10.99.0.1`** → usuario y contraseña.

---

## ⚡ Aplicar el script

1. Reemplaza los valores `CAMBIAR_AQUI` en [`acceso-remoto.rsc`](./acceso-remoto.rsc): tu usuario y la clave pública del cliente.
2. Arrastra el archivo a **Files** y ejecuta:
   ```
   /import file-name=acceso-remoto.rsc
   ```
3. Copia la clave pública del router (`/interface wireguard print`) y ponla en la configuración del cliente.

El script incluye, comentada, la **opción B**: Winbox desde la WAN, pero solo desde una IP pública de confianza (address-list). Sirve si siempre administras desde una IP fija, como la de la oficina.

---

## ✅ Verificación

| Prueba | Dónde | Resultado esperado |
|---|---|---|
| `nc -zv -w 3 IP_PUBLICA 8291` sin túnel | Cliente | **timeout**: Winbox no está expuesto |
| `sudo wg show` | Cliente | `latest handshake` reciente |
| `/interface wireguard peers print` | Router | `last-handshake` con tiempo |
| `ping 10.99.0.1` | Cliente | Responde |
| `nc -zv -w 3 10.99.0.1 8291` | Cliente | **succeeded** |
| Winbox a `10.99.0.1` | Cliente | Entra con usuario y contraseña |

---

## 🛠️ Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| `Destination Host Unreachable` al hacer ping a la WAN del router | El cliente no encuentra el router en la red (falla ARP): cable, IP cambiada o reserva DHCP mal hecha | Revisar `ether1` (flag R), la IP en **IP → DHCP Client** y la MAC de la reserva |
| No hay handshake | Clave pública incompleta (le falta el `=` final), Endpoint o puerto mal, o regla UDP debajo del drop | Una clave tiene 44 caracteres y termina en `=`. Revisar el orden del firewall |
| Hay handshake pero Winbox no entra | Falta `10.99.0.0/24` en IP → Services o en el usuario | Agregarla (paso 5) |
| `wg-quick` advierte que la configuración es legible por otros | Permisos abiertos en la clave o en el `.conf` | `sudo chmod 600 /etc/wireguard/*` |
| El túnel funcionaba y dejó de funcionar | Cambió la IP pública del router | Usar DDNS (ver notas de seguridad) |

---

## 🔐 Notas de seguridad

- **Nunca** abras Winbox (8291) ni SSH (22) a todo internet. Hacia afuera, solo UDP 13231.
- La **clave privada** no se publica: ni en GitHub, ni en capturas, ni en un chat. `/interface wireguard print` no la muestra a menos que uses `show-sensitive`.
- **Un peer por dispositivo.** Si pierdes uno, borra solo su peer.
- **Least privilege** (mínimo privilegio): desde la VPN solo se permite Winbox y SSH, no todo el router.
- **Defense in depth** (defensa en profundidad): firewall, IP → Services y Allowed Address del usuario son tres capas independientes.
- **IP pública dinámica:** activa **IP → Cloud → DDNS Enabled** y usa el nombre `*.sn.mynetname.net` como Endpoint. Ese nombre identifica tu router: no lo publiques.
- Lo que no hace este módulo: no reemplaza un firewall dedicado ni un MFA (autenticación multifactor).

---

⬅️ [02 · Backup automático](../02-backup-automatico/) · [Inicio](../) · [04 · VLANs y colas](../04-vlans-colas/) ➡️

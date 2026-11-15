# 05 · Firewall robusto 🛡️

Llevar el firewall básico del módulo 01 a un nivel más serio: descartar tráfico basura antes de procesarlo, detectar escaneos de puertos, frenar la fuerza bruta y reducir la superficie de ataque.

> **Requisito:** módulos 01 y 04 aplicados.

> ⚠️ **Esto no reemplaza un firewall dedicado** (OPNsense, pfSense, Fortinet). RouterOS no hace inspección profunda de aplicaciones (IPS/IDS), ni filtrado web por categorías, ni sandboxing. Aquí sacamos el máximo provecho de lo que el router sí puede hacer.

---

## 📖 Qué se hace y por qué

### Raw: el filtro antes del filtro
El firewall normal (*filter*) trabaja después del **connection tracking** (*conntrack*): la tabla donde el router anota cada conexión. Anotar cuesta CPU y memoria.

La tabla **raw** actúa **antes** de anotar. Es el portero que saca a los conocidos problemáticos en la puerta, antes de que lleguen a la recepción a pedir turno. Para un CPU de 650 MHz, descartar en raw marca la diferencia ante un escaneo o un flood.

| Tabla | Cuándo actúa | Para qué |
|---|---|---|
| raw | Antes del conntrack | Descartar lo que es basura seguro (barato) |
| filter | Después del conntrack | Decidir con contexto: estado de la conexión, listas, límites |

### Address-lists
Una **address-list** es una lista de IPs con nombre. Las reglas la usan en vez de repetir IPs, y el propio firewall puede agregar IPs a una lista **con tiempo de expiración** (*timeout*). Esa es la base de la detección automática.

### Bogons
Los **bogons** son rangos que nunca deberían venir de internet: redes privadas (RFC 1918), loopback, rangos de documentación, multicast y reservados. Si llegan por la WAN, son tráfico falsificado (*spoofing*) o un error de configuración.

### Port scan y fuerza bruta
- **PSD** (*Port Scan Detection*): suma un "peso" por cada puerto distinto que una IP toca en poco tiempo. Si pasa el umbral, la IP va a `PORT-SCANNERS` por un día.
- **Fuerza bruta a SSH por etapas:** cada conexión nueva sube a la IP de etapa (`etapa1` → `etapa2` → `etapa3`), y cada etapa dura 1 minuto. La 4.ª conexión en menos de un minuto la manda a `BLOQUEADOS` por un día. Un humano que se equivoca una vez no llega a la etapa 3; un bot sí.

### Flags TCP imposibles
Ningún sistema operativo legítimo envía paquetes **NULL** (sin flags), **XMAS** (FIN+PSH+URG), **SYN+FIN** o **SYN+RST**. Los generan herramientas de escaneo (como `nmap -sN` o `-sX`) para identificar el sistema operativo o evadir firewalls.

### Anti-spoofing en la LAN
Un equipo de la LAN solo puede enviar con una IP de nuestras redes. Si una cámara IoT infectada intenta falsificar su IP de origen (por ejemplo, para participar en un ataque DDoS), el router la descarta.

---

## 🗺️ Diseño

| Lista | Contenido | Cómo se llena |
|---|---|---|
| `BOGONS` | 14 rangos reservados | Estática |
| `REDES-LOCALES` | `192.168.10/20/30/40.0/24`, `10.99.0.0/24` | Estática |
| `PORT-SCANNERS` | IPs que escanean la WAN | Dinámica, 1 día |
| `BLOQUEADOS` | IPs con fuerza bruta a SSH | Dinámica, 1 día |
| `ssh-etapa1..3` | Conteo de intentos SSH | Dinámica, 1 minuto |

**Raw (prerouting), en orden:**

| # | Regla | Acción |
|---|---|---|
| 1 | Origen en `BLOQUEADOS` | drop |
| 2 | Origen en `PORT-SCANNERS` | drop |
| 3 | **Solo lab:** origen `192.168.100.0/24` por WAN | accept |
| 4 | Origen en `BOGONS` por WAN | drop |
| 5–8 | TCP NULL, XMAS, SYN+FIN, SYN+RST | drop |
| 9 | DHCP discover (`0.0.0.0` → udp 67) desde LAN | accept |
| 10 | Desde LAN con origen fuera de `REDES-LOCALES` | drop |

**Input (filter), en orden final:**

| # | Regla |
|---|---|
| 0 | accept established/related/untracked |
| 1 | drop invalid |
| 2 | **nuevo:** detectar port scan (WAN) |
| 3–6 | **nuevo:** SSH por etapas → `BLOQUEADOS` |
| 7 | accept ICMP **con límite** (50 cada 5 s, ráfaga de 10) |
| 8 | WG desde WAN (módulo 03) |
| 9 | Admin desde VPN (módulo 03) |
| 10 | admin desde MGMT |
| 11–12 | DNS y DHCP desde LAN |
| 13 | drop todo lo demás |

> 📌 **Por qué la excepción del lab:** la "internet" del laboratorio es la red de la casa (`192.168.100.0/24`), que es un bogon. Sin la regla 3, el router descartaría el DHCP del router de la casa y perdería la WAN. Con una IP pública real, **elimina esa regla**. Si tu ISP te tiene detrás de CGNAT (WAN en `100.64.x.x`), quita también ese rango de `BOGONS`.

---

## 🖱️ Pasos en Winbox

> ⚠️ Safe Mode activado durante todo el módulo.

### 1. Address-lists
**IP → Firewall → pestaña Address Lists → +**
- Name `BOGONS` → cada rango de la tabla (uno por fila, con comentario).
- Name `REDES-LOCALES` → tus redes internas y la del túnel WireGuard.

Las listas dinámicas (`PORT-SCANNERS`, `BLOQUEADOS`, `ssh-etapa*`) no se crean: aparecen solas cuando una regla agrega la primera IP.

### 2. Raw
**IP → Firewall → pestaña Raw → +** (Chain `prerouting` en todas), en el orden de la tabla:
- **Bloqueados:** Advanced → Src. Address List `BLOQUEADOS` → Action `drop`.
- **Bogons:** General → In. Interface List `WAN` · Advanced → Src. Address List `BOGONS` → `drop`.
- **Flags TCP:** General → Protocol `tcp` · Advanced → TCP Flags. Por ejemplo, para NULL marca `fin`, `syn`, `rst` y `ack` con el `!` (que **no** estén).
- **Anti-spoofing:** In. Interface List `LAN` · Src. Address List `!REDES-LOCALES` (marca el `!`) → `drop`. Antes de esta va la excepción de DHCP: Src. Address `0.0.0.0`, Protocol `udp`, Dst. Port `67` → `accept`.

### 3. Detectar port scan
**IP → Firewall → Filter Rules → +**
- General: Chain `input`, Protocol `tcp`, In. Interface List `WAN`.
- Extra → **PSD**: Weight Threshold `21`, Delay Threshold `3s`, Low Port Weight `3`, High Port Weight `1`.
- Action: `add src to address list` → Address List `PORT-SCANNERS` → Timeout `1d`.
- Arrástrala justo debajo de `drop invalid`.

Cada puerto bajo 1024 suma 3 y cada puerto alto suma 1. Si una IP llega a 21 puntos en 3 segundos, es un escaneo.

### 4. Fuerza bruta a SSH
Cuatro reglas en **este orden** (de la etapa más alta a la más baja), todas con Chain `input`, Protocol `tcp`, Dst. Port `22`, Connection State `new` y Action `add src to address list`:

| Orden | Src. Address List | Address List destino | Timeout |
|---|---|---|---|
| 1 | `ssh-etapa3` | `BLOQUEADOS` | 1d |
| 2 | `ssh-etapa2` | `ssh-etapa3` | 1m |
| 3 | `ssh-etapa1` | `ssh-etapa2` | 1m |
| 4 | — | `ssh-etapa1` | 1m |

**Por qué al revés:** si la regla de etapa 1 fuera primero, la misma conexión subiría todas las etapas de golpe. Así cada conexión sube solo un escalón.

> Winbox (8291) no se incluye porque abre varias conexiones por sesión y te bloquearías tú mismo. Ya está protegido: solo es alcanzable desde MGMT y la VPN.

### 5. ICMP con límite
Abre la regla `permitir ICMP` → pestaña Extra → **Limit**: Rate `50`, Time `5s`, Burst `10`, mode `packet`.

Lo que exceda el límite cae en el drop final. El ping sigue funcionando, pero un *ping flood* no satura el CPU.

### 6. Ajustes del kernel
**IP → Settings:**
- **TCP SynCookies** ✅: defensa contra *SYN flood*. El router no reserva memoria hasta que el cliente completa el saludo TCP.
- **RP Filter:** `loose`. Descarta paquetes cuyo origen no tiene ruta de vuelta. Se usa `loose` y no `strict` para no romper el failover del módulo 07.

### 7. Reducir la superficie de ataque
- **IPv6 → Settings → Disable IPv6** ✅. Si no usas IPv6, es una puerta sin firewall configurado.
- **IP → Web Proxy**, **IP → SOCKS**, **IP → UPnP:** desactivados.
- **Tools → RoMON:** desactivado.

---

## ⚡ Aplicar el script

1. Revisa en [`firewall-robusto.rsc`](./firewall-robusto.rsc) la variable `redWanLab`. Con IP pública real, déjala vacía: `""`.
2. Arrastra el archivo a **Files** y ejecuta:
   ```
   /import file-name=firewall-robusto.rsc
   ```

El script incluye, comentado, un ejemplo de excepción entre VLANs (usuarios → IoT).

---

## ✅ Verificación

Hazla desde el **Ubuntu en la red de la casa** (simula a un atacante en internet) contra la IP WAN del router.

| Prueba | Resultado esperado |
|---|---|
| `sudo nmap -sS -p 1-1000 IP_WAN` | La IP del Ubuntu aparece en `PORT-SCANNERS`; los siguientes escaneos no reciben respuesta |
| `sudo nmap -sN IP_WAN` (NULL) | Contador de la regla raw `TCP NULL` sube |
| `for i in 1 2 3 4; do nc -zv -w 2 IP_WAN 22; done` | La IP del Ubuntu pasa a `BLOQUEADOS` (las etapas cuentan aunque el puerto esté cerrado desde la WAN) |
| `ping -f IP_WAN` (flood) | Responde solo una parte; CPU estable |
| **IP → Firewall → Address Lists** | Entradas dinámicas con su timeout |

Para desbloquearte: **Address Lists** → selecciona tu IP en `BLOQUEADOS` o `PORT-SCANNERS` → **Remove**.

> Las pruebas detalladas (Nmap, evidencias) van en el repositorio de auditoría.

---

## 🛠️ Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| El router pierde la WAN después de aplicar | `192.168.100.0/24` está en `BOGONS` y no hay excepción del lab | Crear la regla raw de excepción o vaciar `redWanLab` solo con IP pública real |
| Me bloqueé por SSH | 4 conexiones en un minuto (scripts, `scp` repetidos) | Borrar tu IP de `BLOQUEADOS` desde Winbox |
| Los equipos de la LAN no reciben IP | La regla anti-spoofing está antes de la excepción de DHCP | Revisar el orden en Raw |
| Una red nueva (PPPoE, hotspot) no navega | Su rango no está en `REDES-LOCALES` | Agregarlo a la lista |
| El escaneo desde la red de la casa no se bloquea | La excepción del lab está antes de `PORT-SCANNERS` | Los bloqueos deben ir primero |
| CPU alta | Muchas reglas en filter | Mover a raw lo que se pueda |

---

## 🔐 Notas de seguridad

- **Raw primero:** lo que es basura seguro se descarta antes del conntrack.
- **Bloqueos con timeout:** un bloqueo permanente por IP termina castigando a inocentes (IPs dinámicas, CGNAT). Un día es suficiente para frenar a un bot.
- **No cambies los puertos de servicio** (22, 8291) como medida de seguridad: es *security by obscurity*. Un escaneo los encuentra en segundos. La protección real es que no estén expuestos.
- **Log de lo descartado:** se activa en el módulo 06, junto con el syslog remoto. Sin un destino externo, el log de RAM se llena y se pierde al reiniciar.
- **Revisa el orden** después de cada cambio. Una regla bien escrita en mal lugar no hace nada (o hace daño).
- Lo que **no** hace este módulo: IPS/IDS, inspección TLS, filtrado por aplicación ni por reputación de IPs en tiempo real. Para eso se usa un firewall dedicado o un SIEM (módulo 06, con Wazuh).

---

⬅️ [04 · VLANs y colas](../04-vlans-colas/) · [Inicio](../) · [06 · Monitoreo y logs](../06-monitoreo-logs/) ➡️

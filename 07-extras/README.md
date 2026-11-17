# 07 · Extras 🧩

Tres funciones que usan los proveedores de internet y las empresas, cada una en su propio script:

| Script | Qué hace |
|---|---|
| [`hotspot.rsc`](./hotspot.rsc) | Portal cautivo (*captive portal*) con usuario y contraseña en la red de invitados |
| [`pppoe-server.rsc`](./pppoe-server.rsc) | El router se comporta como un ISP pequeño: los clientes se conectan por PPPoE |
| [`failover-pcc.rsc`](./failover-pcc.rsc) | Dos internets: si uno cae, todo sale por el otro, y con los dos arriba se reparte la carga |

Son **independientes**: aplica solo los que quieras. Todos parten de los módulos 01, 04 y 05.

> ⚠️ El hAP lite tiene 650 MHz y 32 MB de RAM. Puede correr cualquiera de estas funciones para aprender, pero no varias a la vez con muchos usuarios.

---

## 1️⃣ Hotspot (portal cautivo)

### Qué es y por qué
Un **hotspot** obliga a cada equipo a pasar por una página de login antes de navegar, como el WiFi de un hotel o un aeropuerto. Sirve para:
- **Identificar** a cada usuario: quién se conectó, cuándo y cuánto consumió.
- Dar **un usuario por persona** y desactivarlo cuando ya no aplique.
- Limitar **velocidad y tiempo** por usuario.

Funciona así: mientras el equipo no inicia sesión, el router intercepta su navegación y lo redirige a la página de login. Para eso crea reglas dinámicas de firewall y NAT (las que empiezan con `hs-`).

### Diseño

| Elemento | Valor |
|---|---|
| Interfaz | `vlan30-invitados` (WiFi `LAB-Invitados`) |
| Dirección del portal | `192.168.30.1`, nombre `login.invitados.lan` |
| Login | `http-chap`: la contraseña no viaja en texto plano |
| Perfil de usuario | 1 dispositivo por usuario, 2M/5M, sesión de 4 h, inactividad de 15 min |
| IPs | Las entrega el DHCP del módulo 04 (`address-pool=none`) |

### Pasos en Winbox
1. **IP → Hotspot → pestaña Server Profiles → +:** Name `hs-invitados`, Hotspot Address `192.168.30.1`, DNS Name `login.invitados.lan`, HTML Directory `hotspot`. Pestaña Login: solo `HTTP CHAP`.
2. **Pestaña User Profiles → +:** Name `up-invitados`, Shared Users `1`, Rate Limit `2M/5M`, Session Timeout `04:00:00`, Idle Timeout `00:15:00`.
3. **Pestaña Servers → +:** Name `hotspot-invitados`, Interface `vlan30-invitados`, Address Pool `none`, Profile `hs-invitados`, Addresses Per MAC `1`.
4. **Pestaña Users → +:** Server `hotspot-invitados`, nombre, contraseña, Profile `up-invitados`.
5. Si no hay página de login: botón **Reset HTML** del servidor, o **IP → Hotspot → Setup** para que el asistente cree los archivos.

### Verificación
- Celular a `LAB-Invitados` → abre cualquier página `http://` → aparece el login.
- Después de iniciar sesión: **IP → Hotspot → pestaña Active** muestra el usuario, su IP y su consumo.
- Con el mismo usuario en un segundo equipo: rechazado (Shared Users = 1).

### Seguridad
- **El portal no cifra el WiFi.** Mantén WPA2 en `LAB-Invitados`: el hotspot identifica, WPA2 cifra. Un WiFi abierto con portal se puede espiar.
- La página de login es HTTP. Para HTTPS se necesita un certificado válido para el DNS Name; con uno autofirmado el navegador muestra alerta.
- **MAC cookie** y **login por MAC** son cómodos, pero una MAC se falsifica fácilmente. No los uses como autenticación.
- Las reglas `hs-` las gestiona el hotspot: no las muevas ni las borres.
- El hotspot crea **colas dinámicas** por usuario, que van antes que las del módulo 04. La cola `invitados` deja de ver ese tráfico; el límite lo pone el perfil del usuario.

---

## 2️⃣ Servidor PPPoE

### Qué es y por qué
**PPPoE** (*Point-to-Point Protocol over Ethernet*) es lo que usa la mayoría de los ISP: cada cliente se autentica con usuario y contraseña, y recibe su IP y su velocidad. Para un administrador de ISP, montarlo en el lab permite entender el lado del servidor:
- **Autenticación por cliente** (secret): se corta el servicio desactivando el usuario.
- **Una interfaz por sesión**: cada cliente es una interfaz `<pppoe-usuario>`, con su cola y sus contadores.
- Funciona en **capa 2**: el cliente no necesita IP para descubrir el servidor.

En producción, los usuarios y planes suelen vivir en un servidor **RADIUS**, no en el router.

### Diseño

| Elemento | Valor |
|---|---|
| Interfaz | `vlan50-pppoe` (VLAN 50, solo por el trunk ether4) |
| Router | `10.50.0.1` |
| Pool de clientes | `10.50.0.10` – `10.50.0.250` |
| Autenticación | Solo **MSCHAPv2** (PAP y CHAP desactivados) |
| Perfil | 10M/30M por cliente, DNS `10.50.0.1`, `change-tcp-mss`, una sesión por usuario |
| MTU/MRU | 1480 |
| Lista de interfaces | Cada sesión entra a `LAN` (dinámica) |

**Por qué la lista `LAN`:** al entrar a `LAN`, cada cliente hereda las reglas que ya existen: DNS al router sí, internet sí, otras VLANs no, Winbox no.

**Por qué MTU 1480:** PPPoE agrega 8 bytes de encabezado. Con 1500, los paquetes grandes se fragmentan o se pierden, y algunas páginas cargan a medias. `change-tcp-mss` ajusta TCP a ese tamaño.

### Pasos en Winbox
1. **Interfaces → VLAN → +:** `vlan50-pppoe`, VLAN ID 50, Interface `bridge-lan`.
2. **Bridge → VLANs → +:** VLAN IDs 50, Tagged `bridge-lan` y `ether4`.
3. **IP → Pool → +:** `pool-pppoe`, `10.50.0.10-10.50.0.250`.
4. **IP → Firewall → Address Lists → +:** `REDES-LOCALES` → `10.50.0.0/24` (si no, el anti-spoofing del módulo 05 los bloquea).
5. **PPP → pestaña Profiles → +:** Name `perfil-pppoe`, Local Address `10.50.0.1`, Remote Address `pool-pppoe`, DNS Server `10.50.0.1`, Change TCP MSS `yes`, Interface List `LAN`. Pestaña Limits: Rate Limit `10M/30M`, Only One `yes`.
6. **PPP → pestaña PPPoE Servers → +:** Service Name `lab-pppoe`, Interface `vlan50-pppoe`, Default Profile `perfil-pppoe`, Max MTU/MRU `1480`, One Session Per Host ✅, Authentication: solo `mschap2`.
7. **PPP → pestaña Secrets → +:** Name, Password, Service `pppoe`, Profile `perfil-pppoe`.

### Cliente de prueba (Ubuntu en ether4)
```bash
sudo ip link add link <iface> name pppoe50 type vlan id 50
sudo ip link set pppoe50 up
nmcli connection add type pppoe con-name lab-pppoe ifname ppp0 \
    pppoe.parent pppoe50 username USUARIO password CLAVE
nmcli connection up lab-pppoe
ip addr show ppp0          # debe tener 10.50.0.x
```

### Verificación
- **PPP → pestaña Active Connections:** aparece el usuario con su IP.
- **Queues:** aparece una cola dinámica `<pppoe-USUARIO>` con 10M/30M.
- Desde el cliente: internet sí; `ping 192.168.10.1` sí (ICMP); Winbox a `10.50.0.1` no.

### Seguridad
- **Nunca PAP:** envía la contraseña en texto plano. MSCHAPv2 tampoco es fuerte hoy, pero es lo que soportan todos los clientes PPPoE. La protección real es que el medio (la VLAN o la fibra) no sea accesible a terceros.
- **One session per host / Only One:** evita que una misma cuenta se use en varios lugares a la vez.
- **Un servidor PPPoE falso** (*rogue*) en la misma red puede capturar credenciales. Por eso PPPoE va en su propia VLAN y en puertos controlados.
- Contraseñas únicas por cliente; desactiva (no borres) los usuarios suspendidos para conservar el historial.

---

## 3️⃣ Dos internets: failover y balanceo PCC

### Qué es y por qué
- **Failover:** si el internet principal cae, todo sale por el secundario sin intervención.
- **Balanceo de carga:** con los dos arriba, las conexiones se reparten entre ambos.

**PCC** (*Per Connection Classifier*) calcula un hash de cada conexión (aquí: IP de origen + IP de destino) y la asigna a una WAN. La misma conexión **siempre** sale por la misma WAN. Si los paquetes de una sesión salieran por dos IPs públicas distintas, el banco o la página verían "otra persona" y cortarían la sesión.

**Rutas recursivas con check-gateway:** un failover simple solo detecta el **cable** caído. Pero lo normal es que el cable esté bien y el proveedor no tenga internet. Por eso:
1. Cada WAN tiene una **IP de sonda** en internet (`1.0.0.1` para WAN1, `9.9.9.9` para WAN2), alcanzable solo por esa WAN.
2. La ruta por defecto apunta a la sonda y el router le hace ping (`check-gateway=ping`).
3. Si la sonda no responde, la ruta se desactiva y entra la de respaldo.

Es como verificar que el puente del otro lado del río está en pie, no solo que la carretera hasta el río existe.

### Diseño

| Elemento | WAN1 | WAN2 |
|---|---|---|
| Interfaz | `ether1` | `ether3` (sale del bridge) |
| Obtiene IP | DHCP | DHCP |
| IP de sonda | `1.0.0.1` | `9.9.9.9` |
| Distancia en `main` | 1 (principal) | 2 (respaldo) |
| Tabla propia | `to-wan1` | `to-wan2` |

Cada tabla tiene su WAN con distancia 1 y la otra con distancia 2. Así, si una WAN cae, las conexiones marcadas para ella salen por la otra.

**Las rutas las crea un script** (`pcc-rutas`) que se ejecuta cada vez que un DHCP client obtiene o pierde la IP, porque el gateway de cada WAN puede cambiar.

> 📌 **Segunda WAN en el lab:**
> - Debe estar en una **red distinta** a la WAN1. Otro puerto del mismo router de la casa no sirve: tendrías dos interfaces en la misma red.
> - El hAP lite tiene un solo radio y no tiene USB, así que el celular no se puede conectar directo. Usa un router de viaje (o un router viejo) en modo cliente WiFi conectado al hotspot del celular, con su LAN a ether3.
> - Al pasar ether3 a WAN2, deja de ser puerto de usuarios (la VLAN 20 queda en wlan1).

### Pasos en Winbox
1. **Bridge → Ports:** quita `ether3`. **Bridge → VLANs →** VLAN 20 → quita `ether3` de Untagged.
2. **Interfaces → Interface List → +:** `WAN` → `ether3`.
3. **Routing → Tables → +:** `to-wan1` y `to-wan2`, con **FIB** ✅.
4. **System → Scripts → +:** `pcc-rutas`, con el contenido de la versión legible que está en el `.rsc`.
5. **IP → DHCP Client:**
   - `ether1`: Add Default Route `no`, pestaña Advanced → Script `/system script run pcc-rutas`.
   - **+** `ether3`: lo mismo, con Use Peer DNS `no`.
6. **IP → Firewall → Mangle:** las 8 reglas del script, en el mismo orden (marcar conexiones entrantes → PCC → marcar ruteo → output).
7. **System → Scripts →** `pcc-rutas` → **Run Script**.

### Verificación

| Prueba | Resultado esperado |
|---|---|
| **IP → Routes** | Rutas `PCC-WAN1` y `PCC-WAN2` en `main`, `to-wan1` y `to-wan2`; las principales activas (A) |
| Varios speedtests o descargas desde la LAN | **Interfaces:** tráfico en ether1 y ether3 |
| **IP → Firewall → Connections** | Conexiones con marca `wan1-conn` y `wan2-conn` |
| Desconectar internet del router de WAN1 (no el cable) | En segundos, la ruta de WAN1 queda inactiva y todo sale por WAN2 |
| Reconectar | La ruta vuelve sola |
| `/tool traceroute 1.0.0.1` y `9.9.9.9` | Cada uno sale por su WAN |

### Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| Sin internet después de aplicar | El DHCP no disparó el script | Ejecutar `pcc-rutas` a mano y revisar el Log |
| Las VLANs no se ven entre sí (admin no llega a otras) | Falta `!REDES-LOCALES` en las reglas PCC | Revisar las reglas de mangle |
| Páginas que piden login repetido | PCC con puertos, o WAN que cambia | Usar `both-addresses` |
| Todo sale por una sola WAN | La sonda de la otra no responde o falta la ruta en su tabla | **IP → Routes**, filtrar por tabla |
| Las colas del módulo 04 no ven el tráfico de WAN2 | La cola `total` usa `dst=ether1` | Quitar `dst` o crear una cola para `ether3` |

### Seguridad
- **El firewall cubre las dos WAN** porque ambas están en la lista `WAN`: todas las reglas del módulo 05 aplican igual.
- `rp-filter=loose` (módulo 05) es obligatorio. Con `strict`, el router descarta respuestas legítimas que entran por la otra WAN.
- La WAN de respaldo suele ser la más débil (celular, plan básico): mantén el mismo nivel de firewall y monitoréala con Netwatch (módulo 06).
- **PCC necesita FastTrack desactivado:** el tráfico fasttrackeado se salta el mangle y PCC deja de funcionar.

---

## ⚡ Aplicar los scripts

1. Haz un backup (módulo 02).
2. Reemplaza los valores `CAMBIAR_AQUI` del script que vas a usar.
3. Arrástralo a **Files** y ejecuta el que corresponda:
   ```
   /import file-name=hotspot.rsc
   /import file-name=pppoe-server.rsc
   /import file-name=failover-pcc.rsc
   ```

---

⬅️ [06 · Monitoreo y logs](../06-monitoreo-logs/) · [Inicio](../) · ¡Fin de la guía! 🎉

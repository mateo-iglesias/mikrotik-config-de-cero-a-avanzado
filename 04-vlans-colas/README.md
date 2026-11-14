# 04 · VLANs y colas 🧱

Dividir la red en **segmentos aislados** (administración, usuarios, invitados e IoT) y repartir el ancho de banda para que un invitado viendo video no deje sin internet al resto.

> **Requisito:** configuración del módulo 01 aplicada. Conecta tu PC a **ether2** antes de empezar: será el único puerto de administración.

---

## 📖 Qué se hace y por qué

### VLANs
Una **VLAN** (Virtual LAN) divide un mismo switch en varias redes aisladas. Es como un edificio con un solo pasillo pero con puertas de colores: cada quien entra solo por la suya.

| Concepto | Qué es |
|---|---|
| **802.1Q (tag)** | Etiqueta de 4 bytes que se agrega a la trama y dice "soy de la VLAN 20" |
| **Access port** | Puerto de una sola VLAN. El equipo conectado no sabe de VLANs: envía tramas sin etiqueta (*untagged*) |
| **Trunk port** | Puerto que transporta varias VLANs, cada trama con su etiqueta (*tagged*) |
| **PVID** | VLAN que el puerto le asigna a lo que llega sin etiqueta |

**Por qué en seguridad:** si un invitado o una cámara IoT se compromete, queda encerrado en su VLAN y no ve la red de administración. Es **segmentación**, un control básico de cualquier marco de seguridad.

Pero ojo: la VLAN es la **pared**. Si el router enruta entre redes sin filtrar, la pared tiene una puerta abierta. Por eso este módulo también agrega reglas de **forward** (aislamiento).

### Colas
Una **cola** (*queue*) limita y reparte el ancho de banda.

- **Simple queue:** límite por red o por equipo (`max-limit`) con una velocidad garantizada (`limit-at`) y una prioridad.
- **PCQ** (*Per Connection Queue*): dentro de una cola, reparte en partes iguales entre los equipos. Si hay 4 celulares en invitados, cada uno recibe ¼, y uno solo no se come todo el ancho de banda.

### FastTrack vs colas
**FastTrack** acelera el router saltándose el procesamiento normal de los paquetes ya establecidos. Ese "atajo" también se salta las **simple queues**, el mangle y parte del firewall. Por eso en el módulo 01 **no se activó**.

- Con FastTrack: más velocidad y menos CPU, pero las colas no funcionan bien.
- Sin FastTrack: el CPU procesa todo y las colas funcionan.

En un hAP lite con 120 Mb de internet, VLANs por CPU y colas, el router puede quedar cerca de su límite. Mide con un speedtest y revisa la CPU en **Tools → Profile**.

---

## 🗺️ Diseño

| VLAN | Interfaz | Red | Gateway / DNS | Puertos | Lease |
|---|---|---|---|---|---|
| 10 | `vlan10-admin` | `192.168.10.0/24` | `192.168.10.1` | `ether2` (access) | módulo 01 |
| 20 | `vlan20-usuarios` | `192.168.20.0/24` | `192.168.20.1` | `ether3` (access), `wlan1` | 1d |
| 30 | `vlan30-invitados` | `192.168.30.0/24` | `192.168.30.1` | `wlan2-invitados` (virtual AP) | 1h |
| 40 | `vlan40-iot` | `192.168.40.0/24` | `192.168.40.1` | — | 1d |
| trunk | — | — | — | `ether4`: tagged 20, 30, 40 | — |

```
                      ether1 (WAN)
                           │
             [ hAP lite: NAT + firewall + colas ]
                           │
          bridge-lan (VLAN filtering, tagged 10/20/30/40)
     ┌─────────┬───────────┼──────────────┬───────────────┐
  ether2     ether3      ether4         wlan1        wlan2-invitados
 VLAN 10    VLAN 20   trunk 20/30/40   VLAN 20 SSID      VLAN 30 SSID
  admin    usuarios   (pruebas)        LAB-hAP         LAB-Invitados
```

- **La VLAN 1 no se usa.** Es la VLAN por defecto de todos los equipos y el blanco típico de ataques.
- **La VLAN 10 nunca pasa por el trunk.** La administración solo entra por ether2.
- **Listas de interfaces:** `LAN` = las 4 VLAN · `MGMT` (nueva) = `vlan10-admin`.

### Quién puede hablar con quién

| Origen | Router (input) | Otras VLANs | Internet |
|---|---|---|---|
| admin (MGMT) | ✅ todo | ✅ | ✅ |
| usuarios, invitados, IoT | solo DNS, DHCP y ping | ❌ | ✅ |

### Colas (internet de 120 Mb)

| Cola | Red | Prioridad | Garantizado (`limit-at`) | Máximo (`max-limit`) | Tipo |
|---|---|---|---|---|---|
| `total` | las 4 | — | — | subida / 120M | padre |
| `admin` | 10 | 1 (la más alta) | 2M / 10M | subida / 120M | default |
| `usuarios` | 20 | 4 | 5M / 40M | subida / 120M | PCQ |
| `iot` | 40 | 6 | 1M / 2M | 2M / 5M | PCQ |
| `invitados` | 30 | 8 (la más baja) | 1M / 5M | 5M / 20M | PCQ |

Formato: subida / bajada. La suma de los `limit-at` debe ser **menor** que la velocidad real; si tu subida es menor a 9M, baja los `limit-at` de subida.

> 📌 **hAP lite:** su switch chip no hace *bridge VLAN filtering* por hardware. Al activarlo, desaparece la bandera **H** (*hardware offload*) de los puertos y el CPU conmuta todo. A 100 Mbps el equipo lo aguanta; es el costo de tener VLANs también en el WiFi.

---

## 🖱️ Pasos en Winbox

> ⚠️ Haz un **backup** antes (módulo 02). Los pasos 1 a 5 no cortan el acceso. El 6 sí: léelo completo antes de hacerlo.

### 1. Interfaces VLAN
**Interfaces → pestaña VLAN → +**

| Name | VLAN ID | Interface |
|---|---|---|
| `vlan10-admin` | 10 | `bridge-lan` |
| `vlan20-usuarios` | 20 | `bridge-lan` |
| `vlan30-invitados` | 30 | `bridge-lan` |
| `vlan40-iot` | 40 | `bridge-lan` |

Cada interfaz VLAN es la "puerta" del router hacia esa red: ahí va el gateway.

### 2. IP, pools y DHCP (VLAN 20, 30 y 40)
- **IP → Addresses → +:** `192.168.20.1/24` en `vlan20-usuarios`, `192.168.30.1/24` en `vlan30-invitados` y `192.168.40.1/24` en `vlan40-iot`.
- **IP → Pool → +:** `pool-usuarios`, `pool-invitados` y `pool-iot`, cada uno con el rango `.100-.200` de su red.
- **IP → DHCP Server → pestaña DHCP → +:** `dhcp-usuarios`, `dhcp-invitados` y `dhcp-iot`, cada uno con su interfaz, su pool y su Lease Time (tabla de diseño).
- **IP → DHCP Server → pestaña Networks → +:** cada red con Gateway y DNS Servers = IP del router en esa VLAN. Revisa que **DNS None** quede desmarcado.

La VLAN 10 no se toca aquí: su IP y su DHCP se mueven en el paso 6.

### 3. Listas de interfaces y firewall de input
Después de activar las VLANs, el tráfico ya no entra por `bridge-lan` sino por `vlan10-admin`, `vlan20-usuarios`, etc. Si el firewall no lo sabe antes, el drop final te saca.

**Interfaces → pestaña Interface List → Lists → +** → `MGMT`

**Pestaña Interface List → +:**

| List | Interface |
|---|---|
| `LAN` | `vlan10-admin`, `vlan20-usuarios`, `vlan30-invitados`, `vlan40-iot` (una fila por cada una) |
| `MGMT` | `vlan10-admin` |
| `MGMT` | `bridge-lan` (**temporal**, se quita en el paso 7) |

> ⚠️ **Safe Mode** activado.

**IP → Firewall → Filter Rules:**
1. Regla "permitir desde LAN" → In. Interface List: `MGMT` → Comment: `admin desde MGMT`.
2. **+** Chain `input`, Protocol `udp`, Dst. Port `53,67`, In. Interface List `LAN`, Action `accept`, Comment `DNS y DHCP desde LAN`.
3. **+** Igual con Protocol `tcp`, Dst. Port `53`, Comment `DNS TCP desde LAN`.
4. Arrastra las dos nuevas **encima del drop final**.

**Capa 2 solo en MGMT:**
- **IP → Neighbors → Discovery Settings** → Interface: `MGMT`
- **Tools → MAC Server** → MAC Telnet y MAC Winbox → Allowed Interface List: `MGMT`

Desactiva Safe Mode si todo responde.

### 4. Puertos y tabla VLAN del bridge
Mientras **VLAN Filtering** siga desmarcado, el bridge ignora todo esto: es dibujar el plano antes de instalar las puertas.

**Bridge → pestaña Ports →** doble clic en cada puerto → sección **VLAN**:

| Puerto | PVID | Frame Types | Ingress Filtering |
|---|---|---|---|
| `ether2` | 10 | admit only untagged and priority tagged | ✅ |
| `ether3` | 20 | admit only untagged and priority tagged | ✅ |
| `wlan1` | 20 | admit only untagged and priority tagged | ✅ |
| `ether4` | 1 | admit only VLAN tagged | ✅ |

**Bridge → pestaña VLANs → +** (Bridge `bridge-lan`):

| VLAN IDs | Tagged | Untagged |
|---|---|---|
| 10 | `bridge-lan` | `ether2` |
| 20 | `bridge-lan`, `ether4` | `ether3`, `wlan1` |
| 30 | `bridge-lan`, `ether4` | `wlan2-invitados` (después del paso 5) |
| 40 | `bridge-lan`, `ether4` | — |

`bridge-lan` va como *tagged* en todas porque representa al **propio router** conectado al switch: es un trunk del switch hacia el CPU.

### 5. WiFi de invitados (virtual AP)
Un **virtual AP** es un segundo SSID sobre la misma antena: una puerta, dos timbres.

1. **Wireless → Security Profiles → +:** Name `wifi-invitados`, Mode `dynamic keys`, solo `WPA2 PSK`, ciphers solo `aes ccm`, clave **distinta** a la de `LAB-hAP`.
2. **Wireless → WiFi Interfaces → + → Virtual:** Name `wlan2-invitados`, Mode `ap bridge`, SSID `LAB-Invitados`, Master Interface `wlan1`, Security Profile `wifi-invitados`, WPS `disabled`, **Default Forward desmarcado**.
3. **Bridge → Ports → +:** `wlan2-invitados`, PVID `30`, admit only untagged and priority tagged, Ingress Filtering ✅.
4. **Bridge → VLANs →** VLAN 30 → Untagged: `wlan2-invitados`.

### 6. El cambio crítico ⚠️
Hay que hacer tres cambios **a la vez**:
1. Mover `192.168.10.1/24` de `bridge-lan` a `vlan10-admin`.
2. Mover el DHCP de admin a `vlan10-admin`.
3. Activar **VLAN Filtering**.

Por separado, cada uno corta el acceso: es cambiar la cerradura y la llave al mismo tiempo. En Winbox gráfico tendrías que dar tres OK y quedarías afuera después del primero, así que este paso va por **Terminal en una sola línea**:

1. **New Terminal** → **Ctrl+X** (aparece `[Safe Mode taken]`).
2. Pega:
   ```
   /ip address set [find address="192.168.10.1/24"] interface=vlan10-admin; /ip dhcp-server set [find interface=bridge-lan] interface=vlan10-admin; /interface bridge set [find name="bridge-lan"] vlan-filtering=yes
   ```
3. Espera 10–15 s y ejecuta `/system identity print`.
   - Si responde: **Ctrl+X** para salir de Safe Mode y guardar.
   - Si no responde: no toques nada; Safe Mode revierte solo (puede tardar unos minutos en detectar la desconexión).

**Por qué no te corta:** tu PC envía tramas sin etiqueta por ether2, el PVID 10 las mete a la VLAN 10 y llegan a `vlan10-admin`, que ya tiene la misma IP y la misma MAC. Para el firewall entras por `vlan10-admin`, que está en `MGMT`.

### 7. Limpieza y endurecimiento (Safe Mode ✅)
- **Interfaces → Interface List:** borra `MGMT – bridge-lan` (y `LAN – bridge-lan` si existe).
- **Bridge → pestaña Bridge → `bridge-lan` → VLAN:** Frame Types `admit only VLAN tagged`, Ingress Filtering ✅. Así el propio router no acepta tramas sin etiqueta, y la VLAN 1 dinámica (*added by pvid*) desaparece.

### 8. Aislamiento entre VLANs (forward)
Enfoque *default deny*: se cierra todo y se abre solo lo necesario.

**IP → Firewall → Filter Rules → +** (al final de forward):

| Chain | Condición | Action | Comment |
|---|---|---|---|
| forward | In. Interface List `MGMT` | accept | `fwd admin a todo` |
| forward | In. Interface List `LAN`, Out. Interface List `WAN` | accept | `fwd LAN a internet` |
| forward | — | drop | `fwd drop todo lo demas` |

Las respuestas siguen funcionando gracias a la regla *established, related* que está arriba.

### 9. Colas
**Queues → pestaña Simple Queues → +**

1. **Padre** `total`: Target `192.168.10.0/24`, `192.168.20.0/24`, `192.168.30.0/24`, `192.168.40.0/24` · Dst. `ether1` · Max Limit: tu subida / tu bajada.
2. **Hijas** (pestaña Advanced → Parent: `total`), con los valores de la tabla de colas. En `usuarios`, `iot` e `invitados`: pestaña Advanced → Queue Type: `pcq-upload-default` / `pcq-download-default`.

El orden en simple queues es **subida/bajada** (*Target Upload / Target Download*).

---

## ⚡ Aplicar el script

1. Abre [`vlans-colas.rsc`](./vlans-colas.rsc) y cambia `CAMBIAR_AQUI`: la clave del WiFi de invitados y tu velocidad de subida. Revisa también la bajada.
2. Conecta tu PC a **ether2** y haz un backup.
3. Arrastra el archivo a **Files** y ejecuta:
   ```
   /import file-name=vlans-colas.rsc
   ```
4. En el PC: `ipconfig /renew` (Windows) o reconecta el cable.

El script verifica que existan las reglas del módulo 01 y se detiene si no las encuentra.

---

## ✅ Verificación

| Prueba | Dónde | Resultado esperado |
|---|---|---|
| `/interface bridge vlan print` | Router | `current-tagged` y `current-untagged` llenos |
| `/interface bridge port print` | Router | Sin bandera **H**; PVIDs 10/20/20/1/30 |
| `ipconfig` | PC en ether2 | IP `192.168.10.x` |
| Celular en `LAB-Invitados` | Celular | IP `192.168.30.x` e internet |
| `ping 192.168.10.1` desde invitados | Celular | Responde (ICMP permitido) |
| Winbox a `192.168.30.1` desde invitados | Celular / PC | **No** conecta |
| `ping 192.168.10.200` desde invitados | Celular | **No** responde (aislamiento) |
| Ubuntu en ether4 con `sudo ip link add link <iface> name v30 type vlan id 30` + `sudo dhclient v30` | Ubuntu | IP `192.168.30.x` |
| Speedtest en invitados | Celular | Máximo ~20 Mb |
| **Queues → Simple Queues** | Router | Contadores de bytes moviéndose |

---

## 🛠️ Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| Me quedé sin acceso al activar VLAN Filtering | Cambié la IP o el filtrado por separado, o el PC no estaba en ether2 | Esperar a que Safe Mode revierta; si no, Winbox por MAC desde ether2 o reset + restaurar backup |
| `current-tagged` vacío | VLAN Filtering desactivado | Es normal hasta el paso 6 |
| Una VLAN no aparece en `print` | El `add` no quedó | Verificar siempre con `print detail` |
| El PC recibe `169.254.x.x` | El DHCP sigue en `bridge-lan` | Moverlo a `vlan10-admin` |
| Invitados sin IP | wlan1 deshabilitado, o falta `wlan2-invitados` como untagged en la VLAN 30 | Habilitar wlan1 y revisar la tabla VLAN |
| Invitados tienen IP pero no DNS | Falta la regla `DNS y DHCP desde LAN` o quedó debajo del drop | Revisar el orden de input |
| Las colas no limitan | FastTrack activo | Desactivar la regla `fasttrack-connection` |
| Internet más lento que antes | El CPU llega al 100 % (VLANs por CPU + colas) | **Tools → Profile**; bajar límites o quitar la cola padre |

---

## 🔐 Notas de seguridad

- **VLAN hopping** (saltar de VLAN). Tiene dos formas:
  - *Switch spoofing*: el atacante finge ser un trunk.
  - *Double tagging*: mete dos etiquetas para colarse en otra VLAN.

  Se cierra con estas medidas:
  - Los access ports aceptan solo tramas sin etiqueta.
  - Todos los puertos llevan `ingress-filtering`.
  - El bridge solo acepta tramas etiquetadas.
  - No se usa la VLAN 1.
- **Least privilege** (mínimo privilegio): invitados, usuarios e IoT solo le piden al router DNS y DHCP. Winbox y SSH quedan para `MGMT`.
- **Defense in depth** (defensa en profundidad): firewall + IP → Services + Allowed Address del usuario.
- **MAC Winbox y Neighbor Discovery solo en MGMT:** funcionan sin IP. En otra VLAN, un invitado vería el modelo y la versión del router y podría intentar entrar por MAC.
- **Client isolation** (Default Forward desmarcado): los invitados no se ven entre ellos.
- **Clave de invitados distinta** y rotada de vez en cuando. WPS apagado.
- **DHCP starvation:** cada VLAN tiene su pool, así que un ataque desde invitados no deja sin IP a admin.
- La VLAN 10 no sale por el trunk: un equipo en ether4 nunca llega a la administración.
- Las reglas entre VLANs se refinan en el módulo 05 (por ejemplo, usuarios → IoT para un Chromecast).

---

⬅️ [03 · Acceso remoto](../03-acceso-remoto/) · [Inicio](../) · [05 · Firewall robusto](../05-firewall-robusto/) ➡️

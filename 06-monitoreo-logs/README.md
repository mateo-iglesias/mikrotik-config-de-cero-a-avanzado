# 06 · Monitoreo y logs 📊

Saber **qué pasa** en el router: quién entró, qué bloqueó el firewall, cuándo se cayó internet. Los logs salen del router hacia un servidor (**syslog**), donde se guardan, se buscan y, más adelante, se analizan con un SIEM como Wazuh.

> **Requisito:** módulos 01, 04 y 05 aplicados. Un equipo Linux (Ubuntu) en la **VLAN 10 (admin)** como servidor de logs.

---

## 📖 Qué se hace y por qué

### El problema: el log del router vive en RAM
Por defecto, RouterOS guarda el log en **memoria** (RAM): unas 1000 líneas, y se **borra al reiniciar**. Si alguien entra al router y lo reinicia, o si se cae por un ataque, la evidencia desaparece.

- Guardarlo en la flash tampoco es buena idea: son 16 MB y cada escritura la desgasta.
- La solución es enviarlo **fuera** del router, a un equipo que lo guarde.

### Syslog
**Syslog** es el estándar para enviar logs por la red (UDP 514). Es como la caja negra de un avión, pero guardada en tierra: aunque el avión se pierda, el registro queda.

| Pieza | Dónde | Qué hace |
|---|---|---|
| Acción `remote` | Router | Envía cada mensaje al servidor |
| Reglas de logging | Router | Deciden **qué temas** (*topics*) se envían |
| rsyslog | Ubuntu | Recibe y guarda en `/var/log/mikrotik/` |
| logrotate | Ubuntu | Rota los archivos para no llenar el disco |

### Qué conviene registrar

| Topic | Qué contiene | Para qué |
|---|---|---|
| `account` | Logins y logins fallidos (Winbox, SSH) | Detectar accesos y fuerza bruta |
| `firewall` | Lo que registran las reglas con `log=yes` | Ver ataques bloqueados |
| `info`, `warning` | Cambios de configuración (y quién los hizo), interfaces, DHCP | Auditoría de cambios |
| `error`, `critical` | Fallas | Diagnóstico |

### Netwatch
**Netwatch** hace ping a un equipo cada cierto tiempo y ejecuta un script cuando cambia de estado (cae o vuelve). Aquí lo usamos para dejar un aviso en el log, que llega al syslog.

### Herramientas de diagnóstico (sin script)
| Herramienta | Dónde | Para qué |
|---|---|---|
| **Torch** | Tools → Torch | Ver en vivo quién consume ancho de banda en una interfaz (IP, puerto, protocolo) |
| **Packet Sniffer** | Tools → Packet Sniffer | Capturar tráfico y abrirlo en Wireshark |
| **Profile** | Tools → Profile | Ver qué consume CPU |
| **Connections** | IP → Firewall → Connections | Tabla de conexiones activas |
| **Log** | Log | Ver el log en vivo (lo que queda en RAM) |

---

## 🗺️ Diseño

| Elemento | Valor |
|---|---|
| Servidor syslog | Ubuntu en la VLAN 10 (`192.168.10.x`), UDP 514 |
| Origen de los logs | `192.168.10.1` (src-address fija) |
| Formato | BSD syslog (RFC 3164), facility `local0` |
| Archivo en el servidor | `/var/log/mikrotik/hAP-lite-LAB.log`, rotación diaria, 30 días |
| Prefijos del firewall | `FW-IN-DROP`, `FW-FWD-DROP`, `PORTSCAN`, `SSH-BRUTEFORCE` |
| Netwatch | `1.1.1.1` (internet), gateway de la WAN, servidor syslog |

**Por qué el servidor va en la VLAN 10:** los logs contienen información sensible (usuarios, IPs internas, reglas). Enviarlos a la VLAN de usuarios o invitados expondría esa información a equipos menos confiables.

> 📌 En el lab, ether2 es el único puerto de la VLAN 10 y ahí está el PC Windows. Para el Ubuntu tienes dos opciones:
> - Conectar un switch sencillo (no administrable) en ether2.
> - Pasar ether3 a la VLAN 10: PVID `10` y agregarlo como untagged en la VLAN 10. En ese caso ether3 deja de ser de usuarios.

---

## 🖱️ Pasos

### 1. Servidor syslog en Ubuntu
```bash
sudo mkdir -p /var/log/mikrotik
sudo chown syslog:adm /var/log/mikrotik
sudo cp rsyslog-mikrotik.conf /etc/rsyslog.d/10-mikrotik.conf
sudo cp logrotate-mikrotik /etc/logrotate.d/mikrotik
sudo rsyslogd -N1                 # valida la sintaxis
sudo systemctl restart rsyslog
sudo ss -ulnp | grep 514          # debe aparecer rsyslogd escuchando
```
Firewall del Ubuntu: solo el router puede enviar logs.
```bash
sudo ufw allow from 192.168.10.1 to any port 514 proto udp
```
Archivos: [`rsyslog-mikrotik.conf`](./rsyslog-mikrotik.conf) y [`logrotate-mikrotik`](./logrotate-mikrotik). La configuración de rsyslog solo guarda lo que llega desde `192.168.10.1`; cualquier otro origen se descarta.

### 2. Acción remota en el router
**System → Logging → pestaña Actions → +**
- Name: `syslog-ubuntu`
- Type: `remote`
- Remote Address: IP del Ubuntu · Remote Port: `514`
- Src. Address: `192.168.10.1`
- Remote Log Format: `syslog`
- Syslog Facility: `local0`

### 3. Reglas de logging
**System → Logging → pestaña Rules → +** (Action: `syslog-ubuntu` en todas):
`info`, `warning`, `error`, `critical`, `account`, `firewall`, una regla por topic.

En la regla por defecto `info` → `memory`, cambia Topics a `info` + `!firewall`. Así los drops del firewall no llenan la RAM; van solo al servidor.

### 4. Log en el firewall
**IP → Firewall → Filter Rules →** abre cada regla → pestaña Action → **Log** ✅ y **Log Prefix**:

| Regla | Log Prefix |
|---|---|
| drop todo lo demas (input) | `FW-IN-DROP` |
| drop todo lo demas (forward) | `FW-FWD-DROP` |
| detectar port scan | `PORTSCAN` |
| SSH 4.º intento – bloquear 1 día | `SSH-BRUTEFORCE` |

> ⚠️ No actives log en reglas de **accept** muy usadas (como *established*): generarías miles de líneas por minuto y el CPU del hAP lite lo sentiría.

### 5. Netwatch
**Tools → Netwatch → +**
- Host: `1.1.1.1` · Type: `icmp` · Interval: `30s`
- Pestaña **Down** → script: `:log warning "NETWATCH: internet CAIDO"`
- Pestaña **Up** → script: `:log warning "NETWATCH: internet OK"`

Repite con el gateway de la WAN (lo ves en **IP → DHCP Client**) y con la IP del Ubuntu.

---

## ⚡ Aplicar el script

1. Prepara el Ubuntu (paso 1).
2. En [`monitoreo-logs.rsc`](./monitoreo-logs.rsc), cambia `CAMBIAR_AQUI` por la IP del Ubuntu.
3. Arrastra el archivo a **Files** y ejecuta:
   ```
   /import file-name=monitoreo-logs.rsc
   ```

---

## ✅ Verificación

| Prueba | Dónde | Resultado esperado |
|---|---|---|
| `sudo tail -f /var/log/mikrotik/hAP-lite-LAB.log` | Ubuntu | Aparece el mensaje "Modulo 06 aplicado" |
| Login fallido en Winbox | Router → Ubuntu | Línea `login failure for user ...` |
| Cambiar cualquier cosa en Winbox | Ubuntu | Línea con el cambio y el usuario que lo hizo |
| `nmap` a la WAN desde la red de la casa | Ubuntu | Líneas `PORTSCAN` y `FW-IN-DROP` con la IP de origen |
| Desconectar el cable de ether1 | Ubuntu | `NETWATCH: gateway WAN CAIDO` y luego `OK` al reconectar |
| `grep -c FW-IN-DROP /var/log/mikrotik/hAP-lite-LAB.log` | Ubuntu | Conteo de intentos bloqueados |
| `sudo tcpdump -ni any udp port 514` | Ubuntu | Paquetes desde `192.168.10.1` (para diagnosticar) |

---

## 🛠️ Problemas frecuentes

| Síntoma | Causa | Solución |
|---|---|---|
| No llega nada al Ubuntu | `ufw` bloquea el 514, rsyslog no escucha, o el Ubuntu no está en la VLAN 10 | `tcpdump` en el Ubuntu; `sudo ss -ulnp \| grep 514` |
| `tcpdump` ve paquetes pero el archivo no crece | La IP de origen no es `192.168.10.1` o hay permisos mal en la carpeta | Revisar Src. Address en la acción; `chown syslog:adm` |
| `rsyslogd -N1` da error con `imudp` | El módulo ya está cargado en `/etc/rsyslog.conf` | Quitar la línea `module(load="imudp")` del archivo nuevo |
| El log de RAM se llena de `FW-IN-DROP` | Falta el `!firewall` en la regla de memory | Paso 3 |
| CPU alta | Log en reglas con mucho tráfico | Quitar `log=yes` de esas reglas |
| Las horas no coinciden | Reloj del router o del Ubuntu sin NTP | NTP en ambos (módulo 01 y `timedatectl`) |

---

## 🔐 Notas de seguridad

- **Syslog por UDP no se cifra ni se autentica.** En la misma VLAN de administración el riesgo es bajo. Entre sedes o por internet, envíalo **por un túnel** (WireGuard del módulo 03).
- **El servidor de logs es un objetivo:** quien lo controla puede borrar las huellas. Mantenlo en la VLAN admin, actualizado y con acceso restringido.
- **Integridad:** un atacante con acceso al router puede **desactivar** el envío de logs, pero no borrar lo que ya llegó al servidor. Por eso el log vive afuera.
- **Retención:** 30 días es un mínimo razonable para un lab. En empresas, la retención la definen la política interna y la normativa (por ejemplo, ISO 27001 pide definirla y cumplirla).
- **Siguiente paso: SIEM.** Con los logs centralizados, **Wazuh** puede correlacionar eventos y generar alertas, por ejemplo: "5 logins fallidos y luego uno exitoso desde la misma IP". Es el puente hacia el trabajo de un analista SOC (CySA+).
- Revisa el log con regularidad: un log que nadie lee no protege.

---

⬅️ [05 · Firewall robusto](../05-firewall-robusto/) · [Inicio](../) · [07 · Extras](../07-extras/) ➡️

# MikroTik de Cero a Avanzado 🛜

Guía práctica para configurar un **MikroTik hAP lite** desde un equipo reseteado hasta una configuración segura con enfoque empresarial: firewall, acceso remoto, VLANs, colas, backups automáticos, monitoreo y más.

Cada módulo incluye:
- 📖 **Qué se hace y por qué**, explicado de forma sencilla.
- 🖱️ **Pasos en Winbox**, para aprender haciéndolo desde la interfaz gráfica.
- ⚡ **Script `.rsc` listo para importar**, para quien lo necesite rápido.

---

## 📋 Requisitos

| Elemento | Detalle |
|---|---|
| Equipo | MikroTik hAP lite (RB941-2nD). Aplica a la mayoría de equipos con RouterOS |
| Sistema | RouterOS v7 (el módulo 01 explica cómo pasar de v6 a v7) |
| Herramienta | [Winbox 4](https://mikrotik.com/download), disponible para Windows, macOS y Linux |
| Red | Internet por DHCP (puede estar detrás de NAT/CGNAT, sin IP pública) |

**Equipo de laboratorio**

| CPU | RAM | Almacenamiento | Puertos | WiFi |
|---|---|---|---|---|
| MIPS 24Kc · 650 MHz · 1 núcleo | 32 MB | 16 MB | 4 × 100 Mbps | 2.4 GHz |

> ⚠️ El hAP lite es un equipo de gama de entrada. Todas las configuraciones funcionan, pero el rendimiento es limitado; en cada módulo se indica cuando algo consume mucho CPU.

---

## 🗺️ Módulos

| # | Módulo | Contenido |
|---|---|---|
| 01 | [Configuración base](./01-configuracion-base/) | Actualización a v7 (incluye Netinstall), bridge, WAN, DNS, NAT, DHCP, WiFi, NTP, usuario seguro, firewall básico y hardening de servicios |
| 02 | [Backup automático](./02-backup-automatico/) | Backup y export programados, envío por correo o a un servidor externo |
| 03 | [Acceso remoto sin IP pública](./03-acceso-remoto/) | Administrar el router detrás de CGNAT con WireGuard y alternativas |
| 04 | [VLANs y colas](./04-vlans-colas/) | Segmentación de red (administración, usuarios, invitados, IoT) y control de ancho de banda |
| 05 | [Firewall robusto](./05-firewall-robusto/) | Raw, address-lists, bogons, protección contra fuerza bruta y escaneos, reglas entre VLANs |
| 06 | [Monitoreo y logs](./06-monitoreo-logs/) | Logs remotos (syslog), Netwatch, Torch y herramientas de diagnóstico |
| 07 | [Extras](./07-extras/) | Hotspot, servidor PPPoE, failover y balanceo de carga con dos proveedores de internet |

Los módulos están pensados para seguirse **en orden**: cada uno parte de la configuración del anterior.

---

## 🚀 Cómo usar los scripts

**Opción A: router desde cero (recomendada)**
1. Abre el `.rsc` y reemplaza **todos** los valores `CAMBIAR_AQUI` (usuarios, contraseñas, nombres de red).
2. En Winbox, arrastra el archivo a **Files**.
3. Ve a **System → Reset Configuration** → ✅ **No Default Configuration** → en **Run After Reset** elige el script.
4. El router se reinicia y queda configurado.

**Opción B: router con la configuración del módulo anterior**
1. Arrastra el `.rsc` a **Files**.
2. Abre **New Terminal** y ejecuta:
   ```
   /import file-name=nombre-del-script.rsc
   ```

> ⚠️ **Antes de importar cualquier script:**
> - Haz un backup de tu configuración actual.
> - Revisa el script completo: entiende qué hace antes de aplicarlo.
> - No lo apliques sobre un router remoto: puede cambiar IPs y cortar tu acceso.

---

## 🔐 Auditoría de seguridad

La verificación de esta configuración (escaneo de puertos, pruebas del firewall y del WiFi) se documenta en un **repositorio independiente**, dedicado a la auditoría del laboratorio.

---

## ⚖️ Aviso

- Esta guía busca sacar el máximo provecho de la seguridad **dentro de RouterOS**. **No reemplaza** un firewall dedicado (OPNsense, pfSense, Fortinet, etc.).
- Todas las pruebas se realizaron en un **laboratorio propio y aislado**.
- Úsalo bajo tu propia responsabilidad y adapta las configuraciones a tu red.

---

## 👤 Autor

**Anderson Mateo Iglesias Suárez**
Administrador de redes en ISP · Estudiante de Ingeniería de Sistemas · Enfocado en ciberseguridad.

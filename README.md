# MikroTik de Cero a Avanzado 🛜

Guía práctica para configurar un **MikroTik hAP lite** desde un equipo reseteado hasta una configuración segura con enfoque empresarial: firewall, acceso remoto, VLANs, backups y auditoría.

Cada módulo explica **qué se hace y por qué**, los **pasos en Winbox** y un **script `.rsc`** listo para importar si lo necesitas rápido.

---

## 📋 Requisitos

| Elemento | Detalle |
|---|---|
| Equipo | MikroTik hAP lite (RB941-2nD) — aplica a la mayoría de equipos RouterOS |
| Sistema | RouterOS v7 (el módulo 01 explica cómo pasar de v6 a v7) |
| Herramienta | [Winbox 4](https://mikrotik.com/download) — disponible para Windows, macOS y Linux |
| Red | Conexión a internet por DHCP (puede estar detrás de NAT/CGNAT) |

**Especificaciones del equipo de laboratorio**

| CPU | RAM | Almacenamiento | Puertos | WiFi |
|---|---|---|---|---|
| MIPS 24Kc · 650 MHz · 1 núcleo | 32 MB | 16 MB | 4 × 100 Mbps | 2.4 GHz |

> ⚠️ **Limitaciones del hAP lite:** es un equipo de gama de entrada. Todas las configuraciones funcionan, pero el rendimiento es limitado frente a equipos superiores; se indicará en cada módulo cuando algo consuma mucho CPU.

---

## 🗺️ Ruta de módulos

| # | Módulo | Estado |
|---|---|---|
| 01 | [Preparación + configuración base + firewall básico](./01-configuracion-base/) | 🔄 En progreso |
| 02 | Backup automático | ⏳ Pendiente |
| 03 | Acceso remoto sin IP pública | ⏳ Pendiente |
| 04 | VLANs + colas simples | ⏳ Pendiente |
| 05 | Firewall robusto (enfoque empresarial) | ⏳ Pendiente |
| 06 | Monitoreo y logs | ⏳ Pendiente |
| 07 | Extras: Hotspot, PPPoE server, failover | ⏳ Pendiente |
| 08 | Auditoría de seguridad con Nmap | ⏳ Pendiente |

---

## 🚀 Cómo usar los scripts

**Opción A — Router con configuración existente**
1. Arrastra el archivo `.rsc` a **Files** en Winbox.
2. Abre **New Terminal** y ejecuta:
   ```
   /import file-name=nombre-del-script.rsc
   ```

**Opción B — Router desde cero (recomendada)**
1. Sube el `.rsc` a **Files**.
2. Ve a **System → Reset Configuration**.
3. Marca **No Default Configuration** y en **Run After Reset** selecciona el script.
4. El router se reinicia y queda configurado.

> ⚠️ **Antes de importar cualquier script:**
> - Haz un backup de tu configuración actual.
> - Revisa y cambia los valores marcados como `CAMBIAR_AQUI` (contraseñas, nombres de red, IPs).
> - No lo apliques sobre un router remoto: puede cambiar IPs y cortar tu acceso.

---

## ⚖️ Aviso

- Esta guía busca sacar el máximo provecho de la seguridad **dentro de RouterOS**. **No reemplaza** un firewall dedicado (OPNsense, pfSense, Fortinet, etc.).
- Todas las pruebas se realizan en un **laboratorio propio y aislado**.
- Úsalo bajo tu propia responsabilidad.

---

## 👤 Autor

**Anderson Mateo Iglesias Suárez** — Administrador de redes en ISP · Estudiante de Ingeniería de Sistemas · Enfocado en ciberseguridad.

# 🗄️ Backup Automatizado de PostgreSQL

## 📌 Descripción

Script en Bash para automatizar respaldos de bases de datos PostgreSQL en entornos críticos.

- ✅ **Backup completo** diario (a las 00:00)
- ✅ **Backup incremental** cada 15 minutos (cumple RPO)
- ✅ **Cifrado AES-256** antes de subir a la nube
- ✅ **Sincronización a AWS S3 Glacier** (almacenamiento de bajo costo)
- ✅ **Rotación automática** (retención de 7 días en local)
- ✅ **Verificación de integridad** y notificaciones de errores

---

## 🛠️ Tecnologías utilizadas

- **Bash** – Scripting y automatización
- **PostgreSQL** – Motor de base de datos
- **OpenSSL** – Cifrado AES-256
- **AWS S3 Glacier** – Almacenamiento en la nube
- **Cron** – Programación de tareas

---

## ⚙️ Configuración de Cron

```bash
# Backup incremental cada 15 minutos
*/15 * * * * /usr/local/bin/backup_postgresql.sh

# Backup completo diario a medianoche
0 0 * * * /usr/local/bin/backup_postgresql.sh

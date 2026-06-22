#!/bin/bash
# ================================================================
# Script: backup_postgresql_incremental.sh
# Propósito: Backup incremental de PostgreSQL con rotación automática
# Autor: Nelson Bodero - Centro de Cómputo InnovaHealth
# Frecuencia: Cada 15 minutos (cron) + completo diario
# ================================================================

# Variables de configuración
DB_NAME="innovahealth_db"
DB_USER="postgres"
BACKUP_DIR="/backups/postgresql"
S3_BUCKET="s3://innovahealth-backups-encrypted"
RETENTION_DAYS=7
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/var/log/backup_postgresql.log"

# Función de logging
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "===== INICIO BACKUP INCREMENTAL ====="

# Crear directorios si no existen
mkdir -p "$BACKUP_DIR/incremental"
mkdir -p "$BACKUP_DIR/full"

# Determinar tipo de backup (completo a medianoche, incremental el resto)
HOUR=$(date +"%H")
if [ "$HOUR" == "00" ]; then
    BACKUP_TYPE="full"
    BACKUP_FILE="$BACKUP_DIR/full/${DB_NAME}_full_${TIMESTAMP}.sql.gz"
    log_message "Ejecutando backup COMPLETO"

    # Backup completo con pg_dump
    PGPASSWORD=$DB_PASSWORD pg_dump -U "$DB_USER" -h localhost \
        --format=custom --compress=9 "$DB_NAME" | gzip > "$BACKUP_FILE"
else
    BACKUP_TYPE="incremental"
    BACKUP_FILE="$BACKUP_DIR/incremental/${DB_NAME}_inc_${TIMESTAMP}.wal"
    log_message "Ejecutando backup INCREMENTAL (WAL archiving)"

    # Forzar rotación de WAL
    PGPASSWORD=$DB_PASSWORD psql -U "$DB_USER" -c "SELECT pg_switch_wal();" "$DB_NAME" > /dev/null

    # Copiar archivos WAL recientes
    cp /var/lib/postgresql/15/main/pg_wal/0000* "$BACKUP_DIR/incremental/" 2>/dev/null
fi

# Verificar éxito del backup
if [ $? -eq 0 ]; then
    log_message "Backup $BACKUP_TYPE completado exitosamente: $BACKUP_FILE"

    # Cifrar backup (AES-256)
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$BACKUP_FILE" \
        -out "${BACKUP_FILE}.enc" \
        -pass file:/etc/backup_encryption.key

    # Subir a AWS S3 Glacier
    log_message "Sincronizando a S3..."
    aws s3 cp "${BACKUP_FILE}.enc" "$S3_BUCKET/$(basename ${BACKUP_FILE}.enc)" \
        --storage-class GLACIER --quiet

    if [ $? -eq 0 ]; then
        log_message "Backup subido a S3 correctamente"
    else
        log_message "ERROR: Fallo al subir a S3"
        # Notificar vía Slack (opcional)
        curl -X POST https://hooks.slack.com/services/YOUR_WEBHOOK \
            -d "{\"text\":\"⚠️ Fallo backup S3: $DB_NAME\"}"
    fi
else
    log_message "ERROR: Fallo en generación del backup"
    exit 1
fi

# Limpieza de backups antiguos
log_message "Limpiando backups antiguos (>$RETENTION_DAYS días)..."
find "$BACKUP_DIR" -type f -name "*.sql.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_DIR" -type f -name "*.wal" -mtime +$RETENTION_DAYS -delete

# Verificar integridad del backup completo
if [ "$BACKUP_TYPE" == "full" ]; then
    log_message "Verificando integridad del backup..."
    gzip -t "$BACKUP_FILE" 2>/dev/null
    if [ $? -eq 0 ]; then
        log_message "✓ Integridad verificada correctamente"
    else
        log_message "✗ ERROR: Backup corrupto detectado"
        curl -X POST https://hooks.slack.com/services/YOUR_WEBHOOK \
            -d "{\"text\":\"🚨 CRÍTICO: Backup corrupto detectado en $DB_NAME\"}"
    fi
fi

log_message "=== FIN BACKUP (Duración: $SECONDS segundos) ==="  

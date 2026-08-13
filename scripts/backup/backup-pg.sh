#!/usr/bin/env bash
# Nightly PostgreSQL logical backup for ALL databases in the cluster.
# Destination: MinIO via rclone. 35-day retention.
#
# Backups:
#   - /backups/pg/{dbname}_YYYYMMDD_HHMMSS.sql.gz (local staging, 7 days)
#   - minio:wiseconnex-pg-backups/{dbname}_YYYYMMDD_HHMMSS.sql.gz (offsite, 35 days)
#
# Cron: 0 3 * * * /backups/backup-pg.sh >> /backups/backup.log 2>&1

set -euo pipefail

readonly DB_CONTAINER="supabase-8954-db"
readonly LOCAL_DIR="/backups/pg"
readonly REMOTE="minio:wiseconnex-pg-backups"
readonly RETENTION_DAYS=35
readonly STAMP="$(date -u +%Y%m%d_%H%M%S)"

# Databases to backup (add new ones here)
readonly DATABASES=(
    "facturas"
    "exchange_rate"
    "_supabase"
)

mkdir -p "${LOCAL_DIR}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

backup_db() {
    local dbname="$1"
    local BASENAME="${dbname}_${STAMP}.sql.gz"
    local TEMP_FILE="${LOCAL_DIR}/.${BASENAME}.partial"
    local FINAL_FILE="${LOCAL_DIR}/${BASENAME}"

    log "Backing up ${dbname}..."

    # Stream gzip directly to avoid uncompressed dump on disk
    docker exec "${DB_CONTAINER}" pg_dump -U postgres --no-owner --no-privileges "${dbname}" \
        | gzip -9 > "${TEMP_FILE}"

    # Verify dump is non-empty
    test -s "${TEMP_FILE}" || { log "ERROR: empty dump for ${dbname}"; return 1; }

    mv "${TEMP_FILE}" "${FINAL_FILE}"

    # Upload to MinIO with checksum verification
    rclone copyto --checksum "${FINAL_FILE}" "${REMOTE}/${BASENAME}"
    rclone lsf "${REMOTE}/${BASENAME}" | grep -Fxq "${BASENAME}" \
        || { log "ERROR: upload verification failed for ${dbname}"; return 1; }

    log "OK: ${dbname} -> ${REMOTE}/${BASENAME} ($(stat -c %s "${FINAL_FILE}") bytes)"
}

main() {
    log "=== PG backup started ==="

    for db in "${DATABASES[@]}"; do
        backup_db "$db" || log "WARNING: backup of ${db} failed"
    done

    # Prune old local files (>7 days)
    find "${LOCAL_DIR}" -type f -name '*.sql.gz' -mtime +7 -delete 2>/dev/null || true

    # Prune old remote files (>35 days)
    rclone delete "${REMOTE}" --min-age "${RETENTION_DAYS}d" 2>/dev/null || true

    log "=== PG backup finished ==="
}

main

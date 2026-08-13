# Backup stratégie

Ten cuidado, **el backup original de Dokploy2 (`/backups/backup-supabase.sh`) sólo respalda la DB `postgres`** (vacía). Las DBs `facturas`, `_supabase`, y `exchange_rate` no están respaldadas.

## Problema detectado

Antes de mi intervención, en el cron `0 3 * * * /backups/backup-supabase.sh`:
- Línea: `docker exec supabase-8954-db pg_dump -U postgres --no-owner --no-privileges postgres`
- Solo dumpa DB `postgres` (vacía, 0 tablas)
- **DBs `facturas` (38 MB), `_supabase` (14 GB), `exchange_rate` (25 MB) NO se respaldan**

## Solución

`scripts/backup/backup-pg.sh` respalda **TODAS** las DBs:

1. `facturas` — datos de Facturas-de-Dimarys
2. `exchange_rate` — rates de cambio
3. `_supabase` — auth, storage, realtime schemas

Para agregar otra DB, edita el array `DATABASES` en el script.

## Instalación

```bash
# 1. Crear bucket MinIO (si no existe)
rclone mkdir minio:wiseconnex-pg-backups

# 2. Copiar script a dokploy2
scp scripts/backup/backup-pg.sh root@dokploy2:/backups/backup-pg.sh
chmod +x /backups/backup-pg.sh

# 3. Reemplazar el cron existente
crontab -e
# Reemplazar: 0 3 * * * /backups/backup-supabase.sh >> /backups/backup.log 2>&1
# Con:        0 3 * * * /backups/backup-pg.sh >> /backups/backup.log 2>&1

# 4. Verificar
ssh dokploy2 '/backups/backup-pg.sh'  # Run una vez para probar
```

## Verificación de backup

```bash
# Listar backups remotos
rclone lsf --sort-by modtime minio:wiseconnex-pg-backups/ | tail -10

# Test de restore (local)
LATEST=$(rclone lsf --sort-by modtime minio:wiseconnex-pg-backups/ | grep "^facturas_" | tail -1)
rclone copyto "minio:wiseconnex-pg-backups/$LATEST" /tmp/test-restore.sql.gz
gunzip -c /tmp/test-restore.sql.gz | docker exec -i local-postgres psql -U postgres -d facturas
```

## Frecuencia

- **Diaria** (cron 03:00 UTC)
- **Retención 35 días** en MinIO
- **Retención 7 días** local staging

## Lo que NO cubre

| Lo que falta | Cómo |
|-------------|------|
| Backups de configs (dokploy, dokploy2, ssh) | Pendiente: ver plan en `docs/runbook.md` |
| Backup de MinIO bucket mismo | El bucket está en disco externo, protegido por TimeMachine local |
| Backup del repo `exchange-rate-pipeline` | Ya está en GitHub |

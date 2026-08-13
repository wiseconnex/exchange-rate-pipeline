# Operations Runbook

## Daily operations

### Check cron status

```bash
launchctl list | grep wiseconnex.exchange-rate
```

Expected: `com.wiseconnex.exchange-rate` listed (PID = `-` means loaded, next fire at 00:00/06:00/12:00/18:00).

### Verify last capture

```bash
# On dokploy2
docker exec supabase-8954-db psql -U supabase_admin -d exchange_rate -c \
  "SELECT source_key, max(fecha) as latest, max(captured_at) as last_capture FROM exchange_rate_snapshots GROUP BY source_key ORDER BY source_key;"
```

### Check capture log

```bash
tail -20 /tmp/capture-exchange-rate.log
```

### Manual capture

```bash
/Users/wiseconnex/.hermes/scripts/capture-exchange-rate.sh
```

## Common issues

### Cron fails: "ERROR: psql failed"

**Cause:** SSH connection issue or auth failure.

**Fix:**
1. Test SSH: `ssh dokploy2 'whoami'`
2. If fails, check `~/.ssh/shared/config` is readable
3. The script uses `ssh_cmd` helper that tries alias first, falls back to explicit key

### Cron fails: "JWSError JWSInvalidSignature"

**Cause:** Known bug in postgrest 12.2.11 + kong 2.8.1. Intermittent.

**Fix:** Already handled by retry-with-backoff in app. If persistent:
```bash
ssh dokploy2 'cd /etc/dokploy/compose/exchange-rate-bcueot/code && docker compose -p exchange-rate-bcueot up -d --force-recreate rest'
```

### Data appears stale (last update > 24h)

**Fix:**
1. Check launchd: `launchctl list | grep exchange-rate`
2. Manual run: `/Users/wiseconnex/.hermes/scripts/capture-exchange-rate.sh`
3. Check logs: `tail -50 /tmp/capture-exchange-rate.log`

## Adding a new currency pair

1. Add currency (if new):
```sql
INSERT INTO public.currencies (iso_code, name, symbol, decimal_places, is_active)
VALUES ('CAD', 'Canadian Dollar', 'C$', 4, true)
ON CONFLICT (iso_code) DO UPDATE SET is_active = EXCLUDED.is_active;
```

2. Add source (if new):
```sql
INSERT INTO public.exchange_rate_sources (key, name, url, api_key_required, supports_historical, notes)
VALUES ('bank_of_canada', 'Bank of Canada', 'https://www.bankofcanada.ca/valet', FALSE, TRUE, 'CAD/USD official')
ON CONFLICT (key) DO UPDATE SET notes = EXCLUDED.notes;
```

3. Register pair:
```sql
INSERT INTO public.currency_pairs (base_code, quote_code, is_active, min_supported_date, primary_source_key, display_name, description)
VALUES ('USD', 'CAD', TRUE, '1980-01-01', 'bank_of_canada', 'USD to CAD', 'Canadian Dollar')
ON CONFLICT (base_code, quote_code) DO UPDATE SET
    is_active = EXCLUDED.is_active,
    min_supported_date = EXCLUDED.min_supported_date,
    primary_source_key = EXCLUDED.primary_source_key;
```

4. Backfill historical (see `scripts/backfill/`)
5. Update cron if new source needed

## Backfill historical data

### Frankfurter (EUR/USD, USD/MXN, etc.)

```bash
python3 scripts/backfill/frankfurter.py
# Output: /tmp/frankfurter_snapshots.jsonl
# Insert into DB:
psql -h dokploy2 -U supabase_admin -d exchange_rate < /tmp/insert_frankfurter.sql
```

### BCV XLS (USD/VES)

```bash
python3 scripts/backfill/bcv_xls.py
# Output: /tmp/bcv_xls_snapshots.jsonl
# Insert into DB:
psql -h dokploy2 -U supabase_admin -d exchange_rate < /tmp/insert_bcv_xls.sql
```

### FRED (USD/VES fallback)

```bash
python3 scripts/backfill/fred.py
# Output: /tmp/backfill_fred.jsonl
# Insert into DB:
psql -h dokploy2 -U supabase_admin -d exchange_rate < /tmp/insert_fred.sql
```

## Backup and restore

### Backup (already in place)

Dokploy2 runs daily `pg_dump` job at 03:00 UTC:
```
0 3 * * * /backups/backup-exchange-rate.sh >> /backups/backup-exchange-rate.log 2>&1
```

Outputs:
- `/backups/exchange_rate/exchange_rate_YYYYMMDD_HHMMSS.sql.gz` (local staging, 7 days)
- `minio:exchange-rate-backups/` (offsite, 35 days retention)

### Restore test

```bash
# Download latest backup
ssh dokploy2 'podman exec minio-server mc cp minio/exchange-rate-backups/$(ls -t /backups/exchange_rate/ | head -1) /tmp/'

# Restore to local DB
gunzip -c /tmp/exchange_rate_*.sql.gz | docker exec -i local-postgres psql -U postgres -d exchange_rate
```

## Monitoring queries

### Source coverage

```sql
SELECT base_currency, currency_code, source_key, count(*) as snapshots, max(fecha) as latest
FROM exchange_rate_snapshots
GROUP BY base_currency, currency_code, source_key
ORDER BY base_currency, currency_code, source_key;
```

### Active pairs

```sql
SELECT base_code, quote_code, primary_source_key, min_supported_date
FROM currency_pairs
WHERE is_active = TRUE
ORDER BY base_code, quote_code;
```

### Daily capture rate

```sql
SELECT date_trunc('day', captured_at) as day, source_key, count(*) as captures
FROM exchange_rate_snapshots
WHERE captured_at > NOW() - interval '7 days'
GROUP BY day, source_key
ORDER BY day DESC, source_key;
```

## Disaster recovery

### Full restore from offsite

```bash
# 1. List available backups
ssh dokploy2 'rclone lsf minio:exchange-rate-backups/'

# 2. Download latest
LATEST=$(ssh dokploy2 'rclone lsf --sort-by modtime minio:exchange-rate-backups/ | tail -1')
ssh dokploy2 "rclone copy minio:exchange-rate-backups/$LATEST /tmp/restore/"

# 3. Restore to fresh DB
gunzip -c /tmp/restore/$LATEST | docker exec -i NEW_DB_CONTAINER psql -U postgres -d exchange_rate
```

### Reset all data

```sql
TRUNCATE public.exchange_rate_snapshots, public.currency_pairs, public.currencies, public.exchange_rate_sources RESTART IDENTITY CASCADE;
```

Then re-run all migrations + backfill scripts.

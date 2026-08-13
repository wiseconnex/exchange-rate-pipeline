# Exchange Rate Pipeline

Self-hosted multi-currency exchange rate service for the WiseConnex ecosystem.

## What is this?

A complete pipeline that:
1. **Captures** daily exchange rates from multiple public sources (dolarapi.com, Frankfurter, open.er-api.com)
2. **Stores** historical rates in a PostgreSQL database
3. **Exposes** rates via PostgREST REST API
4. **Backfills** historical data on demand

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Cron (launchd on m1max)                                    │
│  └─ capture-exchange-rate.sh (4x/day)                       │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  PostgreSQL (dokploy2)                                      │
│  └─ DB: exchange_rate                                        │
│     ├─ currencies                                            │
│     ├─ currency_pairs                                        │
│     ├─ exchange_rate_sources                                 │
│     └─ exchange_rate_snapshots                               │
│       GET /rest/v1/exchange_rate_snapshots?fecha=eq...      │
└────────────────────┬────────────────────────────────────────┘
                     │
         ┌───────────┼───────────┬─────────────┐
         ▼           ▼           ▼             ▼
     Facturas    SitioWise    Avalúos     (future apps)
```

## Quick start

### 1. Database setup

```bash
# Create database
ssh dokploy2 'docker exec supabase-8954-db psql -U supabase_admin -c "CREATE DATABASE exchange_rate;"'

# Apply schema
psql -h dokploy2 -U supabase_admin -d exchange_rate -f sql/01-extension.sql
psql -h dokploy2 -U supabase_admin -d exchange_rate -f sql/02-schema.sql
psql -h dokploy2 -U supabase_admin -d exchange_rate -f sql/03-seed-currencies.sql
psql -h dokploy2 -U supabase_admin -d exchange_rate -f sql/04-seed-sources.sql
psql -h dokploy2 -U supabase_admin -d exchange_rate -f sql/05-seed-pairs.sql
```

### 2. Deploy service (PostgREST + Kong)

```bash
# Apply docker-compose (similar to supabase-facturas-compose)
ssh dokploy2 'cd /etc/dokploy/compose && git clone https://github.com/wiseconnex/exchange-rate-pipeline.git exchange-rate-bcueot'
```

### 3. Configure cron

```bash
# Copy scripts
cp scripts/capture/*.sh ~/.hermes/scripts/

# Install launchd job
cp launchd/com.wiseconnex.exchange-rate.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.wiseconnex.exchange-rate.plist
```

### 4. Backfill historical data

```bash
# Frankfurter (EUR/USD, USD/MXN, etc. from 1999-01-04)
python3 scripts/backfill/frankfurter.py

# BCV XLS (USD/VES from 2020-03-27)
python3 scripts/backfill/bcv_xls.py

# FRED (USD/VES fallback 2018-2022)
python3 scripts/backfill/fred.py
```

## Contents

```
.
├── README.md
├── docs/
│   ├── API.md              # API endpoints
│   ├── runbook.md          # Operations
│   └── architecture.md     # Design decisions
├── scripts/
│   ├── capture/
│   │   ├── capture-exchange-rate.sh    # Main cron script
│   │   └── ssh_cmd.sh                  # SSH helper
│   └── backfill/
│       ├── frankfurter.py
│       ├── bcv_xls.py
│       └── fred.py
├── sql/
│   ├── 01-extension.sql
│   ├── 02-schema.sql
│   ├── 03-seed-currencies.sql
│   ├── 04-seed-sources.sql
│   └── 05-seed-pairs.sql
├── launchd/
│   └── com.wiseconnex.exchange-rate.plist
└── .github/
    └── workflows/
        └── ci.yml
```

## Data sources

| Source | Pairs | Historical | API key |
|--------|-------|-----------|----------|
| dolarapi.com | USD/VES | 2023-01-03+ | No |
| Frankfurter (ECB) | 30 currencies | 1999-01-04+ | No |
| BCV XLS (Tasas sistema bancario) | USD/VES | 2020-03-27+ | No |
| FRED DEXVZUS | USD/VES | 2018-01-02+ | Yes (free) |
| open.er-api.com | USD/ARS, USD/COP, +30 others | 2026-08-13+ (live only) | No |

## Related projects

- `wiseconnex/Facturas-de-Dimarys` - Primary consumer
- `wiseconnex/supabase-facturas-compose` - Reference compose for Supabase deployments

## License

Internal - WiseConnex

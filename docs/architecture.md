# Architecture

## Why this design

The exchange rate service is part of WiseConnex's local infrastructure. Considerations:

1. **Data as source of truth** — multiple apps need these rates, so we own them
2. **Multi-currency from day 1** — even though only Facturas uses USD/VES today, SitioWise (EU) and Avalúos (CO) will need EUR/USD, USD/COP, etc.
3. **Decoupled from apps** — if Facturas is deprecated, exchange rate service continues for other apps
4. **No vendor lock-in** — no premium APIs (no Bloomberg, no Reuters), all public sources

## Why a separate database

We considered:
- ✅ Separate DB (`exchange_rate`) — chosen
- ❌ Same DB as Facturas (`facturas`) — couples lifecycles
- ❌ Standalone Postgres instance — overkill for 90k rows

The `facturas` DB is dedicated to that app. If we deprecate Facturas, we don't want to lose the exchange rate data. The `exchange_rate` DB lives independently in the same Postgres cluster (shared by Dokploy2), so backup cost is zero.

## Why shared Postgres cluster

The PG instance `supabase-8954-db` is a shared instance for self-hosted Supabase:
- Database `facturas` (38 MB)
- Database `_supabase` (14 GB, internal Supabase data)
- Database `exchange_rate` (~25 MB, growing)

Each database has independent lifecycle but shares the same Postgres process. This is the standard pattern for self-hosted Supabase and saves resources.

## Schema design

### Time series

`exchange_rate_snapshots` is a time-series table. With 90k rows and 8.5 years of history, it's small. We don't need TimescaleDB or partitioning. A simple `INDEX (fecha DESC)` is enough.

### (base, quote, source) tuple

This is the key design decision. Different sources give different rates:
- BCV XLS: 1 USD = 35.87 VES
- FRED: 1 USD = 35.93 VES (slight diff)

We store all sources, exact amounts, and let consumers pick the primary source via `currency_pairs.primary_source_key`.

### Granularity

Daily granularity. Intraday would require a much bigger schema and cron. Not needed for the use case (facturas are processed daily, not in real-time).

## Source selection

| Source | Use case | Historical |
|--------|----------|-----------|
| bcv_xls | Official BCV PDF (when available) | 2020-03-27+ |
| bcv_oficial | dolarapi.com daily cron | 2023-01-03+ |
| fred_dexvzus | Federal Reserve published | 2018-01-02+ |
| frankfurter | European Central Bank | 1999-01-04+ |
| open.er_api | Free multi-currency live | 2026-08-13+ |

When multiple sources have the same date, query by `source_key` to pick the preferred one. Default is `currency_pairs.primary_source_key`.

## Operational peaks

- **Daily cron**: 4x/day (00:00, 06:00, 12:00, 18:00 UTC)
- **Capture time**: ~5 seconds per execution
- **Storage growth**: ~25 rows/day × 14 pairs = ~350 rows/day
- **Backup size**: ~6 MB compressed daily

## Future evolution

When we add more apps:
- **SiteWise (EU)**: Activate EUR/USD, EUR/GBP, EUR/JPY
- **Avalúos (CO)**: Backfill USD/COP (need Banxico API or wait for free source)
- **Other LatAm**: USD/ARS, USD/MXN cron

When scale demands:
- Partitioning by year (if > 10M rows)
- Read replicas for PostgREST
- Edge function wrapper with auth

These are not needed today.

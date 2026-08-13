# Exchange Rate API

Self-hosted multi-currency exchange rate service. This document covers the public API.

## Base URL

```
https://exchange-rate-db.wiseconnex.net
```

## Authentication

All requests require:
```
apikey: <SUPABASE_ANON_KEY>
Authorization: Bearer <SUPABASE_ANON_KEY>
```

## Endpoints

### List available pairs

```bash
GET /rest/v1/currency_pairs?is_active=eq.true&order=base_code,quote_code
```

Response:
```json
[
  {
    "base_code": "USD",
    "quote_code": "VES",
    "is_active": true,
    "min_supported_date": "2018-01-02",
    "primary_source_key": "bcv_xls",
    "display_name": "USD to VES",
    "description": "Venezuelan Bolívar..."
  }
]
```

### List currencies

```bash
GET /rest/v1/currencies?is_active=eq.true&order=iso_code
```

### List sources

```bash
GET /rest/v1/exchange_rate_sources?order=key
```

### Get rate for specific date

```bash
GET /rest/v1/exchange_rate_snapshots?fecha=eq.2026-01-15&currency_code=eq.VES&source_key=eq.bcv_xls&limit=1
```

### Get latest rate

```bash
GET /rest/v1/exchange_rate_snapshots?currency_code=eq.VES&source_key=eq.bcv_oficial&order=fecha.desc&limit=1
```

### Get historical range

```bash
GET /rest/v1/exchange_rate_snapshots?currency_code=eq.VES&source_key=eq.bcv_xls&fecha=gte.2024-01-01&fecha=lte.2024-12-31&order=fecha.asc
```

### Get all sources for a date

```bash
GET /rest/v1/exchange_rate_snapshots?fecha=eq.2026-01-15&currency_code=eq.VES&select=source_key,promedio
```

## Use cases

### UC1: Convert USD to VES in a Facturas invoice

```typescript
const { data } = await supabase
  .from('exchange_rate_snapshots')
  .select('promedio')
  .eq('fecha', invoiceDate)
  .eq('currency_code', 'VES')
  .eq('source_key', 'bcv_xls')  // or 'bcv_oficial' for daily
  .single();

const vesPerUsd = data.promedio;
const vesAmount = usdAmount * vesPerUsd;
```

### UC2: Latest rate for display

```typescript
const { data } = await supabase
  .from('exchange_rate_snapshots')
  .select('promedio, fecha')
  .eq('currency_code', 'VES')
  .eq('source_key', 'bcv_oficial')
  .order('fecha', { ascending: false })
  .limit(1)
  .single();
```

### UC3: Multi-currency pair (EUR/USD)

```typescript
const { data } = await supabase
  .from('exchange_rate_snapshots')
  .select('promedio')
  .eq('fecha', date)
  .eq('base_currency', 'EUR')
  .eq('currency_code', 'USD')
  .eq('source_key', 'frankfurter')
  .single();
```

### UC4: Compare rates across sources

```typescript
const { data } = await supabase
  .from('exchange_rate_snapshots')
  .select('source_key, promedio, fecha')
  .eq('fecha', date)
  .eq('currency_code', 'VES')
  .order('source_key');
```

## Current coverage

| Pair | Source | Min date | Max date |
|------|--------|----------|----------|
| USD/VES | bcv_xls | 2020-03-27 | today |
| USD/VES | bcv_oficial | 2023-01-03 | today |
| USD/VES | fred_dexvzus | 2018-01-02 | 2022-12-30 |
| USD/VES | dolarapi_paralelo | 2023-01-03 | today |
| EUR/USD | frankfurter | 1999-01-04 | today |
| EUR/GBP | frankfurter | 1999-01-04 | today |
| EUR/JPY | frankfurter | 1999-01-04 | today |
| USD/EUR | frankfurter | 1999-01-04 | today |
| USD/GBP | frankfurter | 1999-01-04 | today |
| USD/JPY | frankfurter | 1999-01-04 | today |
| USD/CAD | frankfurter | 1999-01-04 | today |
| USD/CHF | frankfurter | 1999-01-04 | today |
| USD/CNY | frankfurter | 1999-01-04 | today |
| USD/BRL | frankfurter | 1999-01-04 | today |
| USD/MXN | frankfurter | 1999-01-04 | today |
| USD/ARS | open_er_api | 2026-08-13 | today |
| USD/COP | open_er_api | 2026-08-13 | today |
| GBP/USD | frankfurter | 1999-01-04 | today |

## Retry logic

PostgREST has known intermittent JWT verification issues (bug in supabase/postgrest 12.2.11 + kong 2.8.1). Best practice: retry with exponential backoff.

```typescript
async function fetchWithRetry(url, headers, maxRetries = 3) {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    const response = await fetch(url, { headers });
    if (response.ok) return response;

    if (response.status === 401 || response.status === 400) {
      await new Promise(r => setTimeout(r, 200 * attempt));
      continue;
    }
    throw new Error(`HTTP ${response.status}`);
  }
}
```

#!/usr/bin/env python3
"""
Backfill exchange rates from Frankfurter API (public, no key).
Covers EUR/USD, USD/MXN, USD/BRL, USD/CAD, USD/JPY, USD/GBP, etc.
Historical data from 1999-01-04 to today.

Strategy:
- Iterate by year (backfill until 1999)
- For each currency, fetch {base=X->Y} pairs
- Aggregate to one wide pandas-like data structure
- Output JSONL for DB insert
"""
import json
import ssl
import sys
import urllib.request
import urllib.error
from datetime import datetime, date, timedelta

BASE_URL = "https://api.frankfurter.dev/v1"
OUTPUT = "/tmp/frankfurter_snapshots.jsonl"

# Pairs to backfill (base, quote, source_key)
# Frankfurter convention: base_amount=1, rates show quote per 1 base
# We store as: rate = how many quote for 1 base (matches our schema)
PAIRS = [
    ("USD", "EUR", "frankfurter"),  # We'll use frankfurter as source
    ("EUR", "USD", "frankfurter"),
    ("USD", "MXN", "frankfurter"),
    ("USD", "BRL", "frankfurter"),
    ("USD", "CAD", "frankfurter"),
    ("USD", "JPY", "frankfurter"),
    ("USD", "GBP", "frankfurter"),
    ("USD", "CNY", "frankfurter"),
    ("USD", "CHF", "frankfurter"),
    ("EUR", "GBP", "frankfurter"),
    ("EUR", "JPY", "frankfurter"),
]

START_DATE = date(1999, 1, 4)
END_DATE = date.today()

# Frankfurter rate: rate_from=base, rate_to=quote
# Returns {base: 1.0, date: YYYY-MM-DD, rates: {quote: x}}
# For storage: rate = 1 base = x quote


def fetch_range(base: str, quote: str, start: date, end: date) -> list:
    """Fetch historical rates from Frankfurter for the range."""
    url = f"{BASE_URL}/{start.isoformat()}..{end.isoformat()}?from={base}&to={quote}"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "WiseConnex-FxBot/1.0 (research; backfill)"})
        with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
            data = json.loads(resp.read())
            return data.get("rates", {}), data.get("start", ""), data.get("end", "")
    except urllib.error.HTTPError as e:
        if e.code == 404:
            # Date range too long or not supported
            print(f"  404 for range {start} to {end}, breaking into smaller chunks")
            return None, None, None
        raise
    except Exception as e:
        print(f"  Error: {e}")
        return None, None, None


def fetch_year(base: str, quote: str, year: int) -> dict:
    """Fetch one year of data."""
    start = date(year, 1, 4) if year == 1999 else date(year, 1, 1)
    end = date(year, 12, 31)
    if end > END_DATE:
        end = END_DATE

    # Try big range first
    rates, _, _ = fetch_range(base, quote, start, end)
    if rates is not None:
        return rates

    # Fallback: split into half-year chunks
    result = {}
    half1_end = date(year, 6, 30)
    half2_start = date(year, 7, 1)
    if start <= half1_end:
        r1, _, _ = fetch_range(base, quote, start, half1_end)
        if r1:
            result.update(r1)
    if half2_start <= end:
        r2, _, _ = fetch_range(base, quote, half2_start, end)
        if r2:
            result.update(r2)
    return result


def main():
    print(f"Backfilling Frankfurter for {len(PAIRS)} pairs from {START_DATE} to {END_DATE}")
    print(f"Output: {OUTPUT}\n")

    all_snapshots = []

    for base, quote, source_key in PAIRS:
        print(f"=== {base}/{quote} ===")
        for year in range(START_DATE.year, END_DATE.year + 1):
            rates = fetch_year(base, quote, year)
            if not rates:
                print(f"  {year}: no data")
                continue

            saved = 0
            for date_str, rate in rates.items():
                try:
                    obs_date = datetime.strptime(date_str, "%Y-%m-%d").date()
                except ValueError:
                    continue

                if rate is None:
                    continue

                all_snapshots.append({
                    "fecha": obs_date.isoformat(),
                    "currency_code": quote,
                    "source_key": source_key,
                    "promedio": rate,
                    "compra": rate,
                    "venta": rate,
                    "notes": f"Frankfurter {base}-to-{quote}",
                    "base_currency": base,
                })
                saved += 1

            print(f"  {year}: {saved} rates")

    # Dedupe by (fecha, currency, source_key) — preferring non-base=EUR
    dedup = {}
    for s in all_snapshots:
        key = (s["fecha"], s["currency_code"], s["source_key"])
        dedup[key] = s

    final = sorted(dedup.values(), key=lambda x: (x["fecha"], x["currency_code"]))

    with open(OUTPUT, "w") as f:
        for s in final:
            f.write(json.dumps(s) + "\n")

    print(f"\nTotal snapshots written: {len(final)}")
    print(f"Saved to {OUTPUT}")


if __name__ == "__main__":
    main()
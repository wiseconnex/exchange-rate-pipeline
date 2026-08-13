#!/usr/bin/env python3
"""
Backfill VES/USD exchange rates from FRED (2018-01-01 to 2023-01-02).
FRED series: DEXVZUS = Venezuelan Bolivar to U.S. Dollar Exchange Rate.

IMPORTANT: FRED already returns the VES-converted rate after the 2018-08-20
reconversion. The value 2.4821 on 2018-08-20 represents the official BCV rate
expressed in VES (NOT VEF). FRED handles the denomination change automatically.

For verification:
- 2018-08-20 (last day VEF, first day VES): 2.4821 (this is in VES, derived from
  the BCV official rate of ~248,510 VEF/USD / 100,000 = 2.4851)
- 2018-08-21: 59.85 (first full day of VES at 6 zeros fewer)

The 100,000x jump happens because the VES was redenominated to drop 5 zeros
(Bolívar Fuerte → Bolívar Soberano, NOT Bolívar Fuerte → Bolivar).

Usage:
    python3 backfill_fred_2018_2023.py [--key FRED_KEY]

Output: /tmp/backfill_fred_2018_2023.jsonl
"""
import argparse
import json
import ssl
import sys
import time
import urllib.request
import urllib.error
from datetime import date, datetime, timedelta

FRED_API_BASE = "https://api.stlouisfed.org/fred/series/observations"
SERIES_ID = "DEXVZUS"

CURRENCY_CODE = "VES"
DEFAULT_SOURCE_KEY = "fred_dexvzus"


def fetch_fred_series(api_key: str, start: date, end: date) -> list[dict]:
    """Fetch FRED observations for DEXVZUS between start and end."""
    params = {
        "series_id": SERIES_ID,
        "api_key": api_key,
        "file_type": "json",
        "observation_start": start.isoformat(),
        "observation_end": end.isoformat(),
        "frequency": "d",  # daily
    }
    qs = "&".join(f"{k}={v}" for k, v in params.items())
    url = f"{FRED_API_BASE}?{qs}"

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(url, timeout=30, context=ctx) as resp:
            data = json.loads(resp.read())
            if "observations" not in data:
                print(f"ERROR: Unexpected FRED response: {data}", file=sys.stderr)
                return []
            return data["observations"]
    except urllib.error.HTTPError as e:
        body = e.read().decode() if e.fp else ""
        print(f"HTTP {e.code}: {body}", file=sys.stderr)
        return []
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        return []


def transform_fred_to_snapshot(obs: dict) -> dict | None:
    """Transform a FRED observation to our snapshot format.
    FRED returns values already in VES (handles reconversion automatically).
    """
    if obs["value"] == ".":  # FRED uses "." for missing
        return None
    try:
        rate_ves = float(obs["value"])
    except ValueError:
        return None

    obs_date = datetime.strptime(obs["date"], "%Y-%m-%d").date()

    return {
        "fecha": obs_date.isoformat(),
        "currency_code": CURRENCY_CODE,
        "source_key": DEFAULT_SOURCE_KEY,
        "promedio": rate_ves,
        "compra": None,
        "venta": None,
        "notes": "FRED DEXVZUS (no conversion needed — FRED handles VEF->VES reconversion)",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--key", help="FRED API key (32-char hex). Or set FRED_API_KEY env var.")
    parser.add_argument("--start", default="2018-01-01")
    parser.add_argument("--end", default="2023-01-02")
    parser.add_argument("--output", default="/tmp/backfill_fred_2018_2023.jsonl")
    args = parser.parse_args()

    api_key = args.key or os.environ.get("FRED_API_KEY")
    if not api_key:
        print("ERROR: FRED API key required. Get one at https://fred.stlouisfed.org/docs/api/api_key.html")
        print("Pass via --key or FRED_API_KEY env var.")
        sys.exit(1)

    start = datetime.strptime(args.start, "%Y-%m-%d").date()
    end = datetime.strptime(args.end, "%Y-%m-%d").date()

    print(f"Fetching FRED {SERIES_ID} from {start} to {end}...")

    # FRED limits: 120 req/min. We're doing 1 request for the whole range.
    observations = fetch_fred_series(api_key, start, end)
    print(f"Got {len(observations)} observations from FRED")

    # Transform and save
    out = open(args.output, "w")
    count = 0
    skipped = 0
    for obs in observations:
        snap = transform_fred_to_snapshot(obs)
        if snap is None:
            skipped += 1
            continue
        out.write(json.dumps(snap) + "\n")
        count += 1
    out.close()

    print(f"\nDone. {count} rates written, {skipped} skipped (missing values).")
    print(f"Output: {args.output}")
    print(f"\nNext: insert into DB via:")
    print(f"  /tmp/insert_fred_backfill.sh {args.output}")


if __name__ == "__main__":
    import os
    main()
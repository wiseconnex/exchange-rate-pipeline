#!/usr/bin/env python3
"""
Backfill BCV XLS historical exchange rates.

BCV publishes quarterly XLS files at:
https://www.bcv.org.ve/seccionportal/tipo-de-cambio-oficial-del-bcv

URL pattern: https://www.bcv.org.ve/sites/default/files/EstadisticasGeneral/2_1_2{TRIM}{YEAR}_smc.xls
  - TRIM: a/b/c/d for Q1/Q2/Q3/Q4
  - YEAR: 2-digit (e.g., 20 for 2020)

XLS structure:
- Each XLS has ~60 sheets (one per business day)
- Sheet name = date in DDMMYYYY format
- Row 14 = USD: ['', 'USD', 'E.U.A.', 1.0, 1.0, bs_compra, bs_venta]
- Cols 5/6 = bs_compra, bs_venta (BS/USD)

NO RECONVERSION NEEDED: BCV XLS data is already in VES/USD for all dates
in our range (March 2020 onwards). Verified against BCV official historical rates:
- 2020-03-30: 80,069 VES/USD (correct)
- 2022-12-30: 17.04 VES/USD
- 2023-12-29: 35.87 VES/USD
- 2026-08-12: 766.86 VES/USD

Quirks discovered:
- 2020 Q1: only 3 days (BCV started publishing this format 2020-03-27)
- 2021 Q1: only 7 days (publishing glitch)
- 2023 Q3: only 2 days (sheets appear in 2023 Q4 file instead)
- 2026 Q3: 30 days (in progress, current quarter)
- Multiple files may overlap (e.g., 2023-10-02 appears in both 23_c and 23_d)

Output JSONL with: fecha, currency_code, source_key, promedio, compra, venta, notes
"""
import json
import os
import urllib.error
import urllib.request
import ssl
import sys
from datetime import datetime, date
import xlrd

XLS_DIR = "/tmp/bcv_xls"
OUTPUT = "/tmp/bcv_xls_snapshots.jsonl"
BASE_URL = "https://www.bcv.org.ve/sites/default/files/EstadisticasGeneral"

# 27 valid XLS files (we don't have 2026 Q4 yet)
YEARS = [20, 21, 22, 23, 24, 25, 26]
TRIMS = ["a", "b", "c", "d"]


def download_xls(year, trim, out_dir=XLS_DIR):
    """Download one XLS file from BCV."""
    url = f"{BASE_URL}/2_1_2{trim}{year}_smc.xls"
    out = os.path.join(out_dir, f"{year}_{trim}.xls")
    if os.path.exists(out) and os.path.getsize(out) > 10000:
        return out  # already cached

    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=60, context=ctx) as resp:
            data = resp.read()
            with open(out, "wb") as f:
                f.write(data)
        return out
    except Exception as e:
        print(f"  Failed to download {year}_{trim}: {e}")
        return None


def parse_sheet_date(sheet_name):
    try:
        return datetime.strptime(sheet_name, "%d%m%Y").date()
    except ValueError:
        return None


def parse_xls(filepath):
    """Parse a single XLS file, return list of snapshot dicts."""
    snapshots = []
    try:
        wb = xlrd.open_workbook(filepath)
    except Exception as e:
        print(f"  ERROR opening {filepath}: {e}")
        return []

    for sheet_name in wb.sheet_names():
        obs_date = parse_sheet_date(sheet_name)
        if obs_date is None:
            continue

        sheet = wb.sheet_by_name(sheet_name)
        usd_row = None
        for row_idx in range(10, min(30, sheet.nrows)):
            cell = sheet.cell_value(row_idx, 1)
            if isinstance(cell, str) and cell.strip() == "USD":
                usd_row = row_idx
                break

        if usd_row is None:
            continue

        try:
            bs_compra = float(sheet.cell_value(usd_row, 5))
            bs_venta = float(sheet.cell_value(usd_row, 6))
        except (ValueError, IndexError):
            continue

        ves_usd = (bs_compra + bs_venta) / 2

        snapshots.append({
            "fecha": obs_date.isoformat(),
            "currency_code": "VES",
            "source_key": "bcv_xls",
            "promedio": ves_usd,
            "compra": bs_compra,
            "venta": bs_venta,
            "notes": "BCV XLS (already VES/USD, no reconversion)",
        })

    return snapshots


def main():
    os.makedirs(XLS_DIR, exist_ok=True)
    print(f"Downloading XLS files to {XLS_DIR}...")
    for year in YEARS:
        for trim in TRIMS:
            # 2026 Q4 doesn't exist yet
            if year == 26 and trim == "d":
                continue
            download_xls(year, trim)

    print(f"\nParsing XLS files...")
    all_snapshots = []
    files = sorted([f for f in os.listdir(XLS_DIR) if f.endswith(".xls") and f.startswith("2")])
    for f in files:
        path = os.path.join(XLS_DIR, f)
        snapshots = parse_xls(path)
        print(f"  {f}: {len(snapshots)} snapshots")
        all_snapshots.extend(snapshots)

    # Dedupe by fecha (last wins)
    dedup = {}
    for s in all_snapshots:
        dedup[s["fecha"]] = s

    print(f"\nTotal raw: {len(all_snapshots)}")
    print(f"Unique dates: {len(dedup)}")

    with open(OUTPUT, "w") as f:
        for s in dedup.values():
            f.write(json.dumps(s) + "\n")
    print(f"Saved to {OUTPUT}")

    dates = sorted(dedup.keys())
    if dates:
        print(f"Date range: {dates[0]} to {dates[-1]}")


if __name__ == "__main__":
    main()

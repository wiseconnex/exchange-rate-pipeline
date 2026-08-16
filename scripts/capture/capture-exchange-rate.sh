#!/bin/bash
# Exchange Rate Capture - Multi-currency, multi-source
# Cron: 0 6,12,18 * * * (every 6 hours)
#
# Captures latest rates for all active currency pairs from:
#   - dolarapi.com (USD/VES)
#   - Frankfurter (EUR/USD, USD/MXN, USD/BRL, etc.)
#   - open.er-api.com (USD/ARS, USD/COP)
# Writes to Supabase via psql over SSH.

set -euo pipefail

LOG_FILE="${LOG_FILE:-/tmp/capture-exchange-rate.log}"
SOURCE_KEY="${SOURCE_KEY:-dolarapi.com}"
DOKPLOY_HOST="${DOKPLOY_HOST:-178.156.168.27}"
DOKPLOY_SSH_KEY="${DOKPLOY_SSH_KEY:-/Users/wiseconnex/.hermes/diana/secure/dokploy2_root_id_ed25519}"
DOKPLOY_USER="${DOKPLOY_USER:-root}"

# Source shared SSH helper (uses dokploy2 alias, falls back to explicit key)
# This is needed because launchd cannot read ~/.ssh/shared/config under all contexts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/ssh_cmd.sh"

log() { echo "[$(date -u +%FT%TZ)] $*" | tee -a "$LOG_FILE"; }

###############################################################################
# 1. USD/VES via dolarapi.com (today only)
###############################################################################
capture_usd_ves() {
    log "=== Capturing USD/VES via dolarapi.com ==="
    local response fecha promedio
    response=$(curl -sS -m 15 -A "WiseConnex-Cron/1.0" "https://ve.dolarapi.com/v1/dolares/oficial" 2>&1) || {
        log "ERROR: Failed to fetch from dolarapi.com"
        return 1
    }
    promedio=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('promedio',''))" 2>/dev/null)
    fecha=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('fechaActualizacion','').split('T')[0])" 2>/dev/null)

    if [ -z "$promedio" ] || [ -z "$fecha" ]; then
        log "ERROR: Empty rate/fecha: promedio=$promedio fecha=$fecha"
        return 1
    fi

    log "USD/VES: 1 USD = $promedio VES (fecha=$fecha)"

    local sql
    sql=$(cat <<EOF
INSERT INTO public.exchange_rate_snapshots (fecha, base_currency, currency_code, source_key, promedio, compra, venta, notes)
VALUES ('$fecha', 'USD', 'VES', 'bcv_oficial', $promedio, NULL, NULL, 'dolarapi.com live rate')
ON CONFLICT (fecha, base_currency, currency_code, source_key) DO UPDATE SET
    promedio = EXCLUDED.promedio,
    captured_at = NOW();
EOF
)

    ssh_cmd "docker exec -i supabase-8954-db psql -U supabase_admin -d exchange_rate" <<< "$sql" >/dev/null 2>&1 || {
        log "ERROR: psql failed for USD/VES"
        return 1
    }

    log "OK: USD/VES stored"
}

###############################################################################
# 2. All Frankfurter pairs (one call, gets all major currencies)
###############################################################################
capture_frankfurter() {
    log "=== Capturing Frankfurter pairs ==="
    # api.frankfurter.dev (Cloudflare) sufre thundering herd al top-of-hour:
    # a las 00/06/12 UTC responde en 14-15s o muere en timeout. Mitigacion:
    # launchd dispara a :45 (ver plist), timeout generoso y reintentos.
    # El sleep 30 se eliminó al mover el schedule a :45.
    local tmp_json
    tmp_json=$(mktemp)
    local base quote
    local tmp_sql
    tmp_sql=$(mktemp)
    echo "BEGIN;" > "$tmp_sql"
    local ok=1
    for base in USD EUR; do
        case "$base" in
            USD) quotes="EUR,GBP,JPY,CAD,CHF,CNY,BRL,MXN" ;;
            EUR) quotes="USD,GBP,JPY" ;;
        esac
        if curl -sS -m 40 --retry 3 --retry-delay 20 --retry-all-errors \
             -A "WiseConnex-Cron/1.0" \
             "https://api.frankfurter.dev/v1/latest?base=${base}&quotes=${quotes}" \
             -o "${tmp_json}.${base}" 2>>"$LOG_FILE"; then
            python3 - "$base" "${tmp_json}.${base}" >> "$tmp_sql" << 'PYEOF' || ok=0
import json, sys
base, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
date_iso, rates = data['date'], data['rates']
for quote, rate in rates.items():
    if rate is None:
        continue
    print(f"INSERT INTO public.exchange_rate_snapshots (fecha, base_currency, currency_code, source_key, promedio, compra, venta, notes) VALUES ('{date_iso}', '{base}', '{quote}', 'frankfurter', {rate}, {rate}, {rate}, 'Frankfurter live rate') ON CONFLICT (fecha, base_currency, currency_code, source_key) DO UPDATE SET promedio = EXCLUDED.promedio, captured_at = NOW();")
PYEOF
        else
            log "ERROR: Failed to fetch Frankfurter base=$base (3 reintentos)"
            ok=0
        fi
    done
    echo "COMMIT;" >> "$tmp_sql"
    rm -f "${tmp_json}" "${tmp_json}.USD" "${tmp_json}.EUR"

    if [ "$ok" != "1" ]; then
        rm -f "$tmp_sql"
        log "WARNING: Frankfurter capture failed"
        return 1
    fi

    ssh_cmd "docker exec -i supabase-8954-db psql -U supabase_admin -d exchange_rate" < "$tmp_sql" 2>&1 | tail -3 | tee -a "$LOG_FILE"

    rm -f "$tmp_sql"
    log "OK: Frankfurter pairs stored"
}

###############################################################################
# 3. USD/ARS and USD/COP via open.er-api.com (live only)
###############################################################################
capture_open_er_api() {
    log "=== Capturing USD/ARS and USD/COP via open.er-api.com ==="
    local response ars cop
    response=$(curl -sS -m 15 -A "WiseConnex-Cron/1.0" "https://open.er-api.com/v6/latest/USD" 2>&1) || {
        log "ERROR: Failed to fetch from open.er-api.com"
        return 1
    }

    ars=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('rates',{}).get('ARS',''))" 2>/dev/null)
    cop=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin).get('rates',{}).get('COP',''))" 2>/dev/null)

    if [ -z "$ars" ] || [ -z "$cop" ]; then
        log "ERROR: Empty rates: ARS=$ars COP=$cop"
        return 1
    fi

    log "USD/ARS: $ars | USD/COP: $cop"

    local today
    today=$(date -u +%Y-%m-%d)

    local sql
    sql=$(cat <<EOF
INSERT INTO public.exchange_rate_snapshots (fecha, base_currency, currency_code, source_key, promedio, compra, venta, notes)
VALUES
    ('$today', 'USD', 'ARS', 'open_er_api', $ars, NULL, NULL, 'open.er-api.com live rate'),
    ('$today', 'USD', 'COP', 'open_er_api', $cop, NULL, NULL, 'open.er-api.com live rate')
ON CONFLICT (fecha, base_currency, currency_code, source_key) DO UPDATE SET
    promedio = EXCLUDED.promedio,
    captured_at = NOW();
EOF
)

    ssh_cmd "docker exec -i supabase-8954-db psql -U supabase_admin -d exchange_rate" <<< "$sql" >/dev/null 2>&1 || {
        log "ERROR: psql failed for open_er_api"
        return 1
    }

    log "OK: USD/ARS and USD/COP stored"
}

###############################################################################
# Main
###############################################################################
main() {
    log "=== Exchange rate capture started ==="

    capture_usd_ves || log "WARNING: USD/VES capture failed"
    capture_frankfurter || log "WARNING: Frankfurter capture failed"
    capture_open_er_api || log "WARNING: open_er_api capture failed"

    log "=== Exchange rate capture finished ==="
}

main

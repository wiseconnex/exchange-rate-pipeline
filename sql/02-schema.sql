-- Exchange Rate Service: Core schema
-- 2026-08-13: Separate from facturas DB for independent lifecycle

-- ============================================================
-- Currency catalog
-- ============================================================
CREATE TABLE IF NOT EXISTS public.currencies (
    iso_code TEXT PRIMARY KEY,        -- ISO 4217: 'USD', 'VES', 'EUR', ...
    name TEXT NOT NULL,
    symbol TEXT,
    decimal_places INT DEFAULT 2,
    is_active BOOLEAN DEFAULT TRUE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_currencies_active ON public.currencies(is_active) WHERE is_active = TRUE;

-- ============================================================
-- Source catalog
-- ============================================================
CREATE TABLE IF NOT EXISTS public.exchange_rate_sources (
    key TEXT PRIMARY KEY,             -- 'bcv_xls', 'fred_dexvzus', ...
    name TEXT NOT NULL,
    url TEXT,
    api_key_required BOOLEAN DEFAULT FALSE,
    supports_historical BOOLEAN DEFAULT TRUE,
    historical_since DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- Currency pairs catalog (base, quote)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.currency_pairs (
    base_code TEXT NOT NULL,
    quote_code TEXT NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    min_supported_date DATE,
    primary_source_key TEXT,
    display_name TEXT,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (base_code, quote_code),
    FOREIGN KEY (base_code) REFERENCES public.currencies(iso_code),
    FOREIGN KEY (quote_code) REFERENCES public.currencies(iso_code),
    FOREIGN KEY (primary_source_key) REFERENCES public.exchange_rate_sources(key)
);

CREATE INDEX idx_currency_pairs_active ON public.currency_pairs(is_active) WHERE is_active = TRUE;

-- ============================================================
-- Daily snapshots (the main data table)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.exchange_rate_snapshots (
    id BIGSERIAL PRIMARY KEY,
    fecha DATE NOT NULL,
    base_currency TEXT NOT NULL DEFAULT 'USD',
    currency_code TEXT NOT NULL,
    source_key TEXT NOT NULL,
    promedio NUMERIC NOT NULL,
    compra NUMERIC,
    venta NUMERIC,
    raw_response JSONB,
    notes TEXT,
    captured_at TIMESTAMPTZ DEFAULT NOW(),
    FOREIGN KEY (base_currency) REFERENCES public.currencies(iso_code),
    FOREIGN KEY (currency_code) REFERENCES public.currencies(iso_code),
    FOREIGN KEY (source_key) REFERENCES public.exchange_rate_sources(key),
    UNIQUE (fecha, base_currency, currency_code, source_key)
);

CREATE INDEX idx_snapshots_fecha ON public.exchange_rate_snapshots(fecha DESC);
CREATE INDEX idx_snapshots_pair ON public.exchange_rate_snapshots(base_currency, currency_code, fecha DESC);
CREATE INDEX idx_snapshots_source ON public.exchange_rate_snapshots(source_key, fecha DESC);
CREATE INDEX idx_snapshots_captured ON public.exchange_rate_snapshots(captured_at DESC);

-- ============================================================
-- Row Level Security (RLS)
-- ============================================================

-- currencies: read for all
ALTER TABLE public.currencies ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read currencies" ON public.currencies FOR SELECT USING (true);
CREATE POLICY "Service role manages currencies" ON public.currencies FOR ALL USING (auth.role() = 'service_role');

-- sources: read for all
ALTER TABLE public.exchange_rate_sources ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read sources" ON public.exchange_rate_sources FOR SELECT USING (true);
CREATE POLICY "Service role manages sources" ON public.exchange_rate_sources FOR ALL USING (auth.role() = 'service_role');

-- pairs: read for all
ALTER TABLE public.currency_pairs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read pairs" ON public.currency_pairs FOR SELECT USING (true);
CREATE POLICY "Service role manages pairs" ON public.currency_pairs FOR ALL USING (auth.role() = 'service_role');

-- snapshots: read for all, write only service_role
ALTER TABLE public.exchange_rate_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read snapshots" ON public.exchange_rate_snapshots FOR SELECT USING (true);
CREATE POLICY "Service role manages snapshots" ON public.exchange_rate_snapshots FOR ALL USING (auth.role() = 'service_role');

-- ============================================================
-- Grants
-- ============================================================
GRANT SELECT ON public.currencies, public.exchange_rate_sources, public.currency_pairs, public.exchange_rate_snapshots TO anon, authenticated;
GRANT ALL ON public.currencies, public.exchange_rate_sources, public.currency_pairs, public.exchange_rate_snapshots TO service_role;

-- Service role also needs sequence access for BIGSERIAL
GRANT USAGE, SELECT ON SEQUENCE public.exchange_rate_snapshots_id_seq TO service_role;

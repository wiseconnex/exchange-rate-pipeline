-- Seed currency pairs
INSERT INTO public.currency_pairs (base_code, quote_code, is_active, min_supported_date, primary_source_key, display_name, description) VALUES
    -- USD/VES (Facturas primary use case)
    ('USD', 'VES', TRUE, '2018-01-02', 'bcv_xls',
     'USD to VES',
     'Venezuelan Bolívar (official BCV rate). Multiple sources: bcv_xls (2020-2026, most precise), fred_dexvzus (2018-2022, fallback), bcv_oficial (2023+, daily cron)'),

    -- EUR base pairs
    ('EUR', 'USD', TRUE, '1999-01-04', 'frankfurter',
     'EUR to USD',
     'Euro to US Dollar (Frankfurter)'),
    ('EUR', 'GBP', TRUE, '1999-01-04', 'frankfurter',
     'EUR to GBP',
     'Euro to British Pound (Frankfurter)'),
    ('EUR', 'JPY', TRUE, '1999-01-04', 'frankfurter',
     'EUR to JPY',
     'Euro to Japanese Yen (Frankfurter)'),

    -- USD base pairs
    ('USD', 'EUR', TRUE, '1999-01-04', 'frankfurter',
     'USD to EUR',
     'US Dollar to Euro (Frankfurter)'),
    ('USD', 'GBP', TRUE, '1999-01-04', 'frankfurter',
     'USD to GBP',
     'British Pound (Frankfurter)'),
    ('USD', 'JPY', TRUE, '1999-01-04', 'frankfurter',
     'USD to JPY',
     'Japanese Yen (Frankfurter)'),
    ('USD', 'CAD', TRUE, '1999-01-04', 'frankfurter',
     'USD to CAD',
     'Canadian Dollar (Frankfurter)'),
    ('USD', 'CHF', TRUE, '1999-01-04', 'frankfurter',
     'USD to CHF',
     'Swiss Franc (Frankfurter)'),
    ('USD', 'CNY', TRUE, '1999-01-04', 'frankfurter',
     'USD to CNY',
     'Chinese Yuan (Frankfurter)'),
    ('USD', 'BRL', TRUE, '1999-01-04', 'frankfurter',
     'USD to BRL',
     'Brazilian Real (Frankfurter)'),
    ('USD', 'MXN', TRUE, '1999-01-04', 'frankfurter',
     'USD to MXN',
     'Mexican Peso (Frankfurter)'),
    ('USD', 'ARS', TRUE, '2026-08-13', 'open_er_api',
     'USD to ARS',
     'Argentine Peso (open.er-api.com - live only)'),
    ('USD', 'COP', TRUE, '2026-08-13', 'open_er_api',
     'USD to COP',
     'Colombian Peso (open.er-api.com - live only)'),

    -- GBP base pairs
    ('GBP', 'USD', TRUE, '1999-01-04', 'frankfurter',
     'GBP to USD',
     'British Pound inverse (Frankfurter)')
ON CONFLICT (base_code, quote_code) DO UPDATE SET
    is_active = EXCLUDED.is_active,
    min_supported_date = EXCLUDED.min_supported_date,
    primary_source_key = EXCLUDED.primary_source_key,
    display_name = EXCLUDED.display_name,
    description = EXCLUDED.description;

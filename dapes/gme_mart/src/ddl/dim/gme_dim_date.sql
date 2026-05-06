-- DDL: gme_dim_date
-- Trading calendar dimension with holidays and macro events
-- Seeded from CSV (2025-2027), not refreshed daily

CREATE TABLE IF NOT EXISTS gme_dim_date (
    date_key            DATE          PRIMARY KEY,
    dow                 INTEGER,          -- 0=Mon, 6=Sun (DuckDB isodow-1)
    is_trading_day      BOOLEAN,
    is_holiday          BOOLEAN       DEFAULT FALSE,
    is_early_close      BOOLEAN       DEFAULT FALSE,
    holiday_name        VARCHAR,
    has_fomc            BOOLEAN       DEFAULT FALSE,
    has_nfp             BOOLEAN       DEFAULT FALSE,
    has_cpi             BOOLEAN       DEFAULT FALSE,
    has_earnings        BOOLEAN       DEFAULT FALSE,
    week_of_year        INTEGER,
    month               INTEGER,
    quarter             INTEGER
);

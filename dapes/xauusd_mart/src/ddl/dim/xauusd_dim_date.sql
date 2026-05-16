-- DDL: xauusd_dim_date
-- Trading calendar dimension for gold/futures market
-- Reuses NYSE holidays as proxy for COMEX calendar (v1 simplification)

CREATE TABLE IF NOT EXISTS xauusd_dim_date (
    date_key            DATE          PRIMARY KEY,
    dow                 INTEGER,
    is_trading_day      BOOLEAN,
    is_holiday          BOOLEAN       DEFAULT FALSE,
    is_early_close      BOOLEAN       DEFAULT FALSE,
    holiday_name        VARCHAR,
    has_fomc            BOOLEAN       DEFAULT FALSE,
    has_nfp             BOOLEAN       DEFAULT FALSE,
    has_cpi             BOOLEAN       DEFAULT FALSE,
    week_of_year        INTEGER,
    month               INTEGER,
    quarter             INTEGER,
    year                INTEGER
);

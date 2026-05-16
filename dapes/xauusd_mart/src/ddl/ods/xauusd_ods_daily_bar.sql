-- DDL: xauusd_ods_daily_bar
-- Raw daily OHLCV bars ingested from yfinance (GC=F COMEX gold futures)
-- Grain: one row per trade_date
-- [REAL_API] source

CREATE TABLE IF NOT EXISTS xauusd_ods_daily_bar (
    trade_date    DATE          NOT NULL PRIMARY KEY,
    ticker        VARCHAR       NOT NULL,
    provider      VARCHAR       NOT NULL,
    source_symbol VARCHAR,
    open          DOUBLE,
    high          DOUBLE,
    low           DOUBLE,
    close         DOUBLE,
    volume        BIGINT,
    pull_ts_utc   TIMESTAMP
);

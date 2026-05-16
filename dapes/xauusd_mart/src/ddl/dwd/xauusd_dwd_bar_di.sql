-- DDL: xauusd_dwd_bar_di
-- Cleaned daily bar with derived technical indicators (ATR14)
-- Grain: one row per trade_date

CREATE TABLE IF NOT EXISTS xauusd_dwd_bar_di (
    trade_date    DATE          NOT NULL PRIMARY KEY,
    open          DOUBLE        NOT NULL,
    high          DOUBLE        NOT NULL,
    low           DOUBLE        NOT NULL,
    close         DOUBLE        NOT NULL,
    volume        BIGINT,
    tr            DOUBLE,
    atr14         DOUBLE
);

-- DDL: xauusd_dws_regime_1d
-- Daily regime classification: TRENDING vs RANGING via ADX + ATR percentile
-- [THEORETICAL] threshold defaults: ADX >= 25 = trending, ATR percentile bands

CREATE TABLE IF NOT EXISTS xauusd_dws_regime_1d (
    trade_date            DATE          NOT NULL PRIMARY KEY,
    close                 DOUBLE        NOT NULL,
    atr14                 DOUBLE,
    adx14                 DOUBLE,
    atr_percentile_60d    DOUBLE,
    regime                VARCHAR       NOT NULL
);

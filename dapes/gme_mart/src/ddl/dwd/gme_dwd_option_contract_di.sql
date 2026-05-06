-- DDL: gme_dwd_option_contract_di
-- Cleaned daily option contract facts
-- Grain: one row per contract (strike x expiry x type) per day
-- Filters: OI > 0, non-weekly (DTE >= 7)

CREATE TABLE IF NOT EXISTS gme_dwd_option_contract_di (
    pull_date           DATE          NOT NULL,
    ticker              VARCHAR       NOT NULL,
    expiry              DATE          NOT NULL,
    strike              DOUBLE        NOT NULL,
    option_type         VARCHAR       NOT NULL,
    option_symbol       VARCHAR,

    -- Pricing
    bid                 DOUBLE,
    ask                 DOUBLE,
    mid_price           DOUBLE,
    last_trade_price    DOUBLE,

    -- Volume & OI
    volume              INTEGER       DEFAULT 0,
    open_interest       INTEGER       DEFAULT 0,

    -- Greeks (REAL from CBOE)
    implied_vol         DOUBLE,
    delta               DOUBLE,
    gamma               DOUBLE,
    theta               DOUBLE,
    vega                DOUBLE,
    rho                 DOUBLE,
    theo                DOUBLE,

    -- Derived
    dte                 INTEGER,
    spot                DOUBLE,
    gex_contribution    DOUBLE,
    series_type         VARCHAR,      -- MONTHLY / QUARTERLY / LEAP / WARRANT

    -- Provenance
    provider            VARCHAR,
    pull_ts_utc         TIMESTAMP,
    cboe_timestamp      VARCHAR,

    PRIMARY KEY (pull_date, ticker, expiry, strike, option_type)
);

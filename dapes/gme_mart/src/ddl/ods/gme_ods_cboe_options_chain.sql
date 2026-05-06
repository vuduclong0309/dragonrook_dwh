-- DDL: gme_ods_cboe_options_chain
-- Raw CBOE delayed options chain, ingested via MotherDuck httpfs
-- Append-only (incremental by pull_date)
-- Source: cdn.cboe.com/api/global/delayed_quotes/options/GME.json

CREATE TABLE IF NOT EXISTS gme_ods_cboe_options_chain (
    pull_date           DATE          NOT NULL,
    ticker              VARCHAR       NOT NULL DEFAULT 'GME',
    provider            VARCHAR       NOT NULL DEFAULT 'cboe',
    pull_ts_utc         TIMESTAMP,

    -- Raw CBOE fields
    option_symbol       VARCHAR,
    bid                 DOUBLE,
    bid_size            INTEGER,
    ask                 DOUBLE,
    ask_size            INTEGER,
    iv                  DOUBLE,
    open_interest       INTEGER,
    volume              INTEGER,
    delta               DOUBLE,
    gamma               DOUBLE,
    theta               DOUBLE,
    vega                DOUBLE,
    rho                 DOUBLE,
    theo                DOUBLE,
    change              DOUBLE,
    opt_open            DOUBLE,
    opt_high            DOUBLE,
    opt_low             DOUBLE,
    tick                VARCHAR,
    last_trade_price    DOUBLE,
    last_trade_time     VARCHAR,
    percent_change      DOUBLE,
    prev_day_close      DOUBLE,

    -- Parsed from OCC symbol
    expiry              DATE,
    option_type         VARCHAR,
    strike              DOUBLE,

    -- Underlying snapshot
    underlying_close    DOUBLE,
    cboe_timestamp      VARCHAR,

    PRIMARY KEY (pull_date, option_symbol)
);

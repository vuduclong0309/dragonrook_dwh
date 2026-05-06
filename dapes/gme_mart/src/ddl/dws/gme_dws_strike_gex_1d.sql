-- DDL: gme_dws_strike_gex_1d
-- Net GEX by strike, daily aggregation

CREATE TABLE IF NOT EXISTS gme_dws_strike_gex_1d (
    pull_date           DATE          NOT NULL,
    ticker              VARCHAR       NOT NULL,
    strike              DOUBLE        NOT NULL,
    expiry              DATE          NOT NULL,
    dte                 INTEGER,
    series_type         VARCHAR,
    call_gex            DOUBLE,
    put_gex             DOUBLE,
    net_gex             DOUBLE,
    total_oi            INTEGER,
    avg_iv              DOUBLE,
    gex_rank            INTEGER,

    PRIMARY KEY (pull_date, ticker, strike, expiry)
);

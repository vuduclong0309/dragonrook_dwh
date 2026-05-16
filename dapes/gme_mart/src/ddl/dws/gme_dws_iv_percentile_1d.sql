-- DDL: gme_dws_iv_percentile_1d
-- IV percentile rank vs rolling 252-day trading history
-- Grain: (pull_date, ticker, expiry_bucket)

CREATE TABLE IF NOT EXISTS gme_dws_iv_percentile_1d (
    pull_date           DATE          NOT NULL,
    ticker              VARCHAR       NOT NULL,
    expiry_bucket       VARCHAR       NOT NULL,

    spot                DOUBLE,
    iv_atm              DOUBLE,
    atm_strike          DOUBLE,

    history_days        INTEGER,
    iv_percentile_252d  DOUBLE,

    iv_avg_trailing     DOUBLE,
    iv_min_trailing     DOUBLE,
    iv_max_trailing     DOUBLE,

    iv_regime           VARCHAR,

    PRIMARY KEY (pull_date, ticker, expiry_bucket)
);

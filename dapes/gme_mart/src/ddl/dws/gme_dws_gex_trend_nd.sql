-- DDL: gme_dws_gex_trend_nd
-- Rolling N-day GEX trend for regime detection
-- Pattern: Shopee order_mart _nd (rolling window aggregation)

CREATE TABLE IF NOT EXISTS gme_dws_gex_trend_nd (
    pull_date                   DATE          NOT NULL,
    ticker                      VARCHAR       NOT NULL,
    spot                        DOUBLE,
    net_gex                     DOUBLE,
    max_pain_strike             DOUBLE,
    pc_ratio                    DOUBLE,

    -- 5-day trailing averages
    net_gex_avg_5d              DOUBLE,
    spot_avg_5d                 DOUBLE,
    pc_ratio_avg_5d             DOUBLE,

    -- Day-over-day deltas
    net_gex_delta_1d            DOUBLE,
    spot_delta_1d               DOUBLE,

    -- Regime classification
    gex_regime                  VARCHAR,      -- POSITIVE_EXPANDING / POSITIVE_STABLE / NEGATIVE_EXPANDING / NEGATIVE_STABLE / NEUTRAL

    -- Max pain convergence
    max_pain_distance_pct       DOUBLE,

    -- Context
    trailing_days               INTEGER,

    PRIMARY KEY (pull_date, ticker)
);

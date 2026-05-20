-- DDL: gme_dws_warrant_monitor_1d
-- Daily warrant position monitoring
-- Position values from dbt vars (not hardcoded)

CREATE TABLE IF NOT EXISTS gme_dws_warrant_monitor_1d (
    pull_date               DATE          NOT NULL PRIMARY KEY,
    ticker                  VARCHAR       NOT NULL,
    spot                    DOUBLE,
    warrant_strike          DOUBLE,
    warrant_qty             INTEGER,
    warrant_expiry          DATE,
    dte                     INTEGER,
    intrinsic_total         DOUBLE,
    moneyness_pct           DOUBLE,
    distance_to_strike_pct  DOUBLE,
    moneyness               VARCHAR,      -- ITM / NEAR_MONEY / OTM
    theta_regime            VARCHAR,      -- LOW / MEDIUM / HIGH
    share_position_value    DOUBLE,
    total_position_value    DOUBLE,

    -- IV context (Phase 1.5, from NEAR bucket)
    iv_atm                  DOUBLE,
    iv_percentile_252d      DOUBLE,
    iv_regime               VARCHAR,
    iv_history_days         INTEGER
);

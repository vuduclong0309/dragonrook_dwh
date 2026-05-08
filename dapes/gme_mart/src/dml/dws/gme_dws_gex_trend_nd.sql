-- DML: Rolling N-day GEX trend (adapted from Shopee order_mart _nd pattern)
-- Tracks net GEX, max pain, P/C ratio over trailing days for regime detection
-- Corresponding DDL: src/ddl/dws/gme_dws_gex_trend_nd.sql

WITH daily AS (
    SELECT
        pull_date,
        ticker,
        spot,
        max_pain_strike,
        net_gex,
        top_gex_strike,
        pc_ratio
    FROM {{ ref('gme_dws_daily_snapshot_1d') }}
)
SELECT
    d.pull_date,
    d.ticker,
    d.spot,
    d.net_gex,
    d.max_pain_strike,
    d.pc_ratio,

    -- 5-day trailing averages (1 trading week)
    AVG(d2.net_gex)          AS net_gex_avg_5d,
    AVG(d2.spot)             AS spot_avg_5d,
    AVG(d2.pc_ratio)         AS pc_ratio_avg_5d,

    -- Day-over-day deltas
    d.net_gex - LAG(d.net_gex) OVER (
        PARTITION BY d.ticker ORDER BY d.pull_date
    )                         AS net_gex_delta_1d,
    d.spot - LAG(d.spot) OVER (
        PARTITION BY d.ticker ORDER BY d.pull_date
    )                         AS spot_delta_1d,

    -- GEX regime classification
    CASE
        WHEN d.net_gex > 0 AND d.net_gex > AVG(d2.net_gex) THEN 'POSITIVE_EXPANDING'
        WHEN d.net_gex > 0 THEN 'POSITIVE_STABLE'
        WHEN d.net_gex < 0 AND d.net_gex < AVG(d2.net_gex) THEN 'NEGATIVE_EXPANDING'
        WHEN d.net_gex < 0 THEN 'NEGATIVE_STABLE'
        ELSE 'NEUTRAL'
    END                       AS gex_regime,

    -- Max pain convergence trend
    ABS(d.spot - d.max_pain_strike) / d.spot * 100 AS max_pain_distance_pct,

    -- Row count for context (how many days of history)
    COUNT(d2.pull_date)       AS trailing_days

FROM daily d
LEFT JOIN daily d2
    ON d2.ticker = d.ticker
   AND d2.pull_date BETWEEN d.pull_date - INTERVAL 5 DAY AND d.pull_date
GROUP BY d.pull_date, d.ticker, d.spot, d.net_gex, d.max_pain_strike, d.pc_ratio

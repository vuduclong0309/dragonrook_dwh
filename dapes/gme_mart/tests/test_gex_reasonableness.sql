-- DQC: GEX reasonableness — fail if latest net_gex exceeds 3σ from 5-day rolling mean
-- [THEORETICAL] threshold: 3 standard deviations covers 99.7% of normal variation
-- Adapted from Shopee DQC outlier detection pattern (delta-based alerting)

WITH daily_gex AS (
    SELECT
        pull_date,
        ticker,
        SUM(net_gex) AS total_net_gex
    FROM {{ ref('gme_dws_strike_gex_1d') }}
    GROUP BY pull_date, ticker
),
rolling_stats AS (
    SELECT
        d.pull_date,
        d.ticker,
        d.total_net_gex,
        AVG(d2.total_net_gex)    AS mean_5d,
        STDDEV(d2.total_net_gex) AS stddev_5d,
        COUNT(d2.pull_date)      AS trailing_days
    FROM daily_gex d
    LEFT JOIN daily_gex d2
        ON d2.ticker = d.ticker
       AND d2.pull_date BETWEEN d.pull_date - INTERVAL 5 DAY AND d.pull_date - INTERVAL 1 DAY
    GROUP BY d.pull_date, d.ticker, d.total_net_gex
)
SELECT
    pull_date,
    ticker,
    total_net_gex,
    mean_5d,
    stddev_5d,
    trailing_days,
    ABS(total_net_gex - mean_5d) / NULLIF(stddev_5d, 0) AS z_score
FROM rolling_stats
WHERE trailing_days >= 3
  AND stddev_5d > 0
  AND ABS(total_net_gex - mean_5d) / stddev_5d > 3.0
  AND pull_date = (SELECT MAX(pull_date) FROM daily_gex)
LIMIT 1

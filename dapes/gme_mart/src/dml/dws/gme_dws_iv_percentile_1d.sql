-- DML: IV Percentile Rank (Phase 1.5)
-- Grain: (pull_date, ticker, expiry_bucket)
-- Lookback: 252 trading days via INTERVAL 365 calendar days [THEORETICAL]
-- ATM-nearest MONTHLY call as IV benchmark per bucket

WITH option_with_bucket AS (
    SELECT
        pull_date,
        ticker,
        spot,
        strike,
        implied_vol,
        dte,
        CASE
            WHEN dte BETWEEN 7 AND 45  THEN 'NEAR'
            WHEN dte BETWEEN 46 AND 90 THEN 'MID'
            WHEN dte > 90              THEN 'FAR'
        END AS expiry_bucket,
        ROW_NUMBER() OVER (
            PARTITION BY pull_date, ticker,
                CASE
                    WHEN dte BETWEEN 7 AND 45  THEN 'NEAR'
                    WHEN dte BETWEEN 46 AND 90 THEN 'MID'
                    WHEN dte > 90              THEN 'FAR'
                END
            ORDER BY ABS(strike - spot) ASC, dte ASC
        ) AS atm_rank
    FROM {{ ref('gme_dwd_option_contract_di') }}
    WHERE option_type = 'call'
      AND implied_vol > 0
      AND implied_vol IS NOT NULL
      AND series_type = 'MONTHLY'
),

daily_iv AS (
    SELECT
        pull_date,
        ticker,
        spot,
        implied_vol AS iv_atm,
        strike      AS atm_strike,
        expiry_bucket
    FROM option_with_bucket
    WHERE atm_rank = 1
      AND expiry_bucket IS NOT NULL
)

SELECT
    d.pull_date,
    d.ticker,
    d.expiry_bucket,
    d.spot,
    d.iv_atm,
    d.atm_strike,

    COUNT(d2.pull_date)                                                 AS history_days,

    CASE
        WHEN COUNT(d2.pull_date) < 252 THEN NULL
        ELSE ROUND(
            SUM(CASE WHEN d2.iv_atm < d.iv_atm THEN 1 ELSE 0 END)
            * 100.0
            / NULLIF(COUNT(d2.pull_date) - 1, 0),
            2
        )
    END                                                                 AS iv_percentile_252d,

    ROUND(AVG(d2.iv_atm), 6)                                           AS iv_avg_trailing,
    MIN(d2.iv_atm)                                                      AS iv_min_trailing,
    MAX(d2.iv_atm)                                                      AS iv_max_trailing,

    CASE
        WHEN COUNT(d2.pull_date) < 252 THEN 'INSUFFICIENT_DATA'
        WHEN SUM(CASE WHEN d2.iv_atm < d.iv_atm THEN 1 ELSE 0 END)
             * 100.0 / NULLIF(COUNT(d2.pull_date) - 1, 0) < 25 THEN 'IV_LOW'
        WHEN SUM(CASE WHEN d2.iv_atm < d.iv_atm THEN 1 ELSE 0 END)
             * 100.0 / NULLIF(COUNT(d2.pull_date) - 1, 0) > 75 THEN 'IV_HIGH'
        ELSE 'IV_NORMAL'
    END                                                                 AS iv_regime

FROM daily_iv d
LEFT JOIN daily_iv d2
    ON  d2.ticker       = d.ticker
    AND d2.expiry_bucket = d.expiry_bucket
    AND d2.pull_date BETWEEN d.pull_date - INTERVAL 365 DAY AND d.pull_date
GROUP BY d.pull_date, d.ticker, d.expiry_bucket, d.spot, d.iv_atm, d.atm_strike

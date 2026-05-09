-- DML: IV Percentile Rank (Phase 1.5 enhancement from PRD)
-- Answers: "Is IV cheap or expensive right now?" relative to history
-- Uses ATM-nearest call IV as the benchmark
-- Lookback: trailing 252 trading days (1 year) — graceful with smaller samples
--
-- IV percentile < 25 = cheap (favorable for buying options)
-- IV percentile > 75 = expensive (favorable for selling / avoid buying)

WITH atm_iv AS (
    -- Pick the ATM-nearest call for each day (closest strike to spot)
    SELECT
        pull_date,
        ticker,
        spot,
        implied_vol AS iv_atm,
        strike,
        ABS(strike - spot) AS distance_from_atm,
        ROW_NUMBER() OVER (
            PARTITION BY pull_date, ticker
            ORDER BY ABS(strike - spot) ASC, dte ASC
        ) AS atm_rank
    FROM {{ ref('gme_dwd_option_contract_di') }}
    WHERE option_type = 'call'
      AND implied_vol > 0
      AND implied_vol IS NOT NULL
      AND series_type = 'MONTHLY'  -- use monthly series for stability
),
daily_iv AS (
    SELECT pull_date, ticker, spot, iv_atm, strike AS atm_strike
    FROM atm_iv
    WHERE atm_rank = 1
)
SELECT
    d.pull_date,
    d.ticker,
    d.spot,
    d.iv_atm,
    d.atm_strike,

    -- Percentile rank vs trailing history
    PERCENT_RANK() OVER (
        PARTITION BY d.ticker
        ORDER BY d.iv_atm
    ) * 100                                                     AS iv_percentile_all,

    -- Stats for context
    COUNT(*) OVER (PARTITION BY d.ticker)                       AS history_days,
    AVG(d2.iv_atm)                                              AS iv_avg_trailing,
    MIN(d2.iv_atm)                                              AS iv_min_trailing,
    MAX(d2.iv_atm)                                              AS iv_max_trailing,

    -- Regime label
    CASE
        WHEN COUNT(*) OVER (PARTITION BY d.ticker) < 10 THEN 'INSUFFICIENT_DATA'
        WHEN PERCENT_RANK() OVER (PARTITION BY d.ticker ORDER BY d.iv_atm) < 0.25 THEN 'IV_LOW'
        WHEN PERCENT_RANK() OVER (PARTITION BY d.ticker ORDER BY d.iv_atm) > 0.75 THEN 'IV_HIGH'
        ELSE 'IV_NORMAL'
    END                                                         AS iv_regime

FROM daily_iv d
LEFT JOIN daily_iv d2
    ON d2.ticker = d.ticker
   AND d2.pull_date BETWEEN d.pull_date - INTERVAL 252 DAY AND d.pull_date
GROUP BY d.pull_date, d.ticker, d.spot, d.iv_atm, d.atm_strike

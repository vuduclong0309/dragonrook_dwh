-- DML: Options Flow Pressure Proxy (Codex Enhancement #3)
-- Detects unusual options activity via OI delta + volume/OI ratio
-- NOTE: This is a PROXY, not confirmed institutional flow.
-- CBOE snapshot data does not carry order-side or institution flags.
-- Labels: UNUSUAL_FLOW, POSITION_BUILD, TRADING_CHURN, NORMAL

WITH contract_day AS (
    SELECT
        pull_date,
        ticker,
        option_symbol,
        expiry,
        strike,
        option_type,
        spot,
        dte,
        volume,
        open_interest,
        LAG(open_interest) OVER (
            PARTITION BY ticker, option_symbol ORDER BY pull_date
        )                                                               AS prev_open_interest,
        delta,
        gamma,
        implied_vol,
        mid_price,
        series_type
    FROM {{ ref('gme_dwd_option_contract_di') }}
)
SELECT
    pull_date,
    ticker,
    expiry,
    strike,
    option_type,
    spot,
    dte,
    series_type,
    volume,
    open_interest,
    open_interest - COALESCE(prev_open_interest, open_interest)         AS oi_delta_1d,
    volume * ABS(COALESCE(delta, 0))                                    AS delta_weighted_volume,
    volume * ABS(COALESCE(gamma, 0))                                    AS gamma_weighted_volume,
    CASE
        WHEN volume >= 500 AND open_interest > 0
         AND volume >= open_interest * 0.5 THEN 'UNUSUAL_FLOW'
        WHEN open_interest - COALESCE(prev_open_interest, open_interest) >= 100
            THEN 'POSITION_BUILD'
        WHEN volume > 0
         AND open_interest - COALESCE(prev_open_interest, open_interest) <= 0
            THEN 'TRADING_CHURN'
        ELSE 'NORMAL'
    END                                                                 AS flow_pressure_label
FROM contract_day
WHERE dte >= 7
  AND prev_open_interest IS NOT NULL  -- need prior day for comparison

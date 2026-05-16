-- Sanity check: gold price should be between $500 and $10000
-- Catches data corruption or wrong ticker ingestion
SELECT
    trade_date,
    close
FROM {{ ref('xauusd_dwd_bar_di') }}
WHERE close < 500 OR close > 10000

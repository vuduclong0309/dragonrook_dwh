-- DQC: Duplication test for DWD fact table
-- PK = (pull_date, ticker, expiry, strike, option_type)
-- Adapted from Shopee order_mart dqc_*.py pattern

SELECT
    pull_date,
    ticker,
    expiry,
    strike,
    option_type,
    COUNT(*) AS cnt
FROM {{ ref('gme_dwd_option_contract_di') }}
GROUP BY pull_date, ticker, expiry, strike, option_type
HAVING COUNT(*) > 1

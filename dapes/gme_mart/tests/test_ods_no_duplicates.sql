-- DQC: Duplication test (adapted from Shopee validation_framework duplication_test)
-- Ensures no duplicate option symbols per pull_date in ODS
-- Failure = upsert logic broken

SELECT
    pull_date,
    option_symbol,
    COUNT(*) AS cnt
FROM {{ ref('gme_ods_cboe_options_chain') }}
WHERE option_symbol IS NOT NULL
GROUP BY pull_date, option_symbol
HAVING COUNT(*) > 1

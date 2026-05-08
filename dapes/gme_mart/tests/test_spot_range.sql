-- DQC: Spot price sanity check
-- GME historically $10-$500. Anything outside = bad data or parsing error.
-- Adapted from Shopee validation_framework logic validation pattern

SELECT
    pull_date,
    ticker,
    spot
FROM {{ ref('gme_dwd_option_contract_di') }}
WHERE spot < 5 OR spot > 500
LIMIT 1

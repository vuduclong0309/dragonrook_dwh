-- DQC: IV percentile must be in [0, 100] when not NULL
-- Rows returned = failures

SELECT
    pull_date,
    ticker,
    expiry_bucket,
    iv_percentile_252d
FROM {{ ref('gme_dws_iv_percentile_1d') }}
WHERE iv_percentile_252d IS NOT NULL
  AND (iv_percentile_252d < 0 OR iv_percentile_252d > 100)
LIMIT 1

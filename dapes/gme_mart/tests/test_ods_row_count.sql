-- DQC: Row count baseline (adapted from Shopee validation_framework row_count_test)
-- CBOE GME chain should return 800-2000 rows per pull
-- Too few = source down or parsing failure
-- Too many = duplicate ingestion

SELECT
    pull_date,
    COUNT(*) AS row_count
FROM {{ ref('gme_ods_cboe_options_chain') }}
GROUP BY pull_date
HAVING COUNT(*) < 500 OR COUNT(*) > 3000

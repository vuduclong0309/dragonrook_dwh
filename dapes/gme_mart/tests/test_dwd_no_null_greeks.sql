-- DQC: Null rate check on critical fields (CBOE should provide all Greeks)
-- Adapted from Shopee item_mart_dim_dqc_data_loss pattern
-- If > 5% nulls in gamma/delta/iv, data quality is degraded

WITH null_rates AS (
    SELECT
        pull_date,
        COUNT(*) AS total,
        SUM(CASE WHEN gamma IS NULL THEN 1 ELSE 0 END) AS null_gamma,
        SUM(CASE WHEN delta IS NULL THEN 1 ELSE 0 END) AS null_delta,
        SUM(CASE WHEN implied_vol IS NULL THEN 1 ELSE 0 END) AS null_iv
    FROM {{ ref('gme_dwd_option_contract_di') }}
    GROUP BY pull_date
)
SELECT *
FROM null_rates
WHERE null_gamma * 1.0 / total > 0.05
   OR null_delta * 1.0 / total > 0.05
   OR null_iv * 1.0 / total > 0.05

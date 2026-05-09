-- DML: GEX Flip Alert Layer (Codex Enhancement #1)
-- Detects regime transitions in dealer gamma exposure
-- POSITIVE flip = dealers go long gamma (stabilizing)
-- NEGATIVE flip = dealers go short gamma (amplifying moves)
-- Value: direct warrant exit timing signal

WITH regime AS (
    SELECT
        pull_date,
        ticker,
        spot,
        net_gex,
        net_gex_avg_5d,
        net_gex_delta_1d,
        gex_regime,
        LAG(net_gex) OVER (PARTITION BY ticker ORDER BY pull_date)      AS prev_net_gex,
        LAG(gex_regime) OVER (PARTITION BY ticker ORDER BY pull_date)   AS prev_gex_regime,
        max_pain_distance_pct,
        trailing_days
    FROM {{ ref('gme_dws_gex_trend_nd') }}
)
SELECT
    pull_date,
    ticker,
    spot,
    net_gex,
    prev_net_gex,
    gex_regime,
    prev_gex_regime,
    net_gex_delta_1d,
    max_pain_distance_pct,
    CASE
        WHEN prev_net_gex < 0 AND net_gex > 0 THEN 'GEX_FLIP_POSITIVE'
        WHEN prev_net_gex > 0 AND net_gex < 0 THEN 'GEX_FLIP_NEGATIVE'
        WHEN net_gex < 0 AND net_gex_delta_1d < 0 THEN 'NEGATIVE_GEX_WORSENING'
        WHEN gex_regime != prev_gex_regime AND prev_gex_regime IS NOT NULL THEN 'REGIME_CHANGE'
        ELSE 'NO_ALERT'
    END AS alert_type
FROM regime
WHERE trailing_days >= 2

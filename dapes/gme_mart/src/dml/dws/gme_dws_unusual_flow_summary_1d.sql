-- DML: Unusual Flow Summary — aggregated from flow_pressure_1d
-- Adapted from Shopee Kimball e-commerce: aggregate fact table pattern
-- (<1% of detail rows, 100x faster queries)
-- Pre-computes daily flow signals for briefing skill

WITH flow_detail AS (
    SELECT *
    FROM {{ ref('gme_dws_flow_pressure_1d') }}
),
unusual AS (
    SELECT
        pull_date,
        ticker,
        COUNT(*) AS unusual_flow_count,
        SUM(volume) AS unusual_flow_volume,
        SUM(oi_delta_1d) AS unusual_flow_oi_delta,
        SUM(delta_weighted_volume) AS unusual_delta_volume
    FROM flow_detail
    WHERE flow_pressure_label = 'UNUSUAL_FLOW'
    GROUP BY pull_date, ticker
),
position_build AS (
    SELECT
        pull_date,
        ticker,
        COUNT(*) AS position_build_count,
        SUM(oi_delta_1d) AS position_build_oi_delta,
        -- Top position build strike
        (SELECT strike FROM flow_detail f2
         WHERE f2.pull_date = f1.pull_date AND f2.ticker = f1.ticker
           AND f2.flow_pressure_label = 'POSITION_BUILD'
         ORDER BY ABS(f2.oi_delta_1d) DESC LIMIT 1) AS top_build_strike
    FROM flow_detail f1
    WHERE flow_pressure_label = 'POSITION_BUILD'
    GROUP BY pull_date, ticker
),
totals AS (
    SELECT
        pull_date,
        ticker,
        COUNT(*) AS total_contracts,
        SUM(volume) AS total_volume,
        SUM(CASE WHEN option_type = 'call' THEN volume ELSE 0 END) AS call_volume,
        SUM(CASE WHEN option_type = 'put' THEN volume ELSE 0 END) AS put_volume
    FROM flow_detail
    GROUP BY pull_date, ticker
)
SELECT
    t.pull_date,
    t.ticker,
    t.total_contracts,
    t.total_volume,
    t.call_volume,
    t.put_volume,
    ROUND(t.call_volume * 1.0 / NULLIF(t.put_volume, 0), 2) AS volume_call_put_ratio,

    COALESCE(u.unusual_flow_count, 0) AS unusual_flow_count,
    COALESCE(u.unusual_flow_volume, 0) AS unusual_flow_volume,
    COALESCE(u.unusual_delta_volume, 0) AS unusual_delta_volume,

    COALESCE(pb.position_build_count, 0) AS position_build_count,
    COALESCE(pb.position_build_oi_delta, 0) AS position_build_oi_delta,
    pb.top_build_strike,

    -- Signal strength
    CASE
        WHEN COALESCE(u.unusual_flow_count, 0) >= 5 THEN 'HIGH_ACTIVITY'
        WHEN COALESCE(u.unusual_flow_count, 0) >= 2 THEN 'MODERATE_ACTIVITY'
        ELSE 'NORMAL'
    END AS flow_signal

FROM totals t
LEFT JOIN unusual u ON t.pull_date = u.pull_date AND t.ticker = u.ticker
LEFT JOIN position_build pb ON t.pull_date = pb.pull_date AND t.ticker = pb.ticker

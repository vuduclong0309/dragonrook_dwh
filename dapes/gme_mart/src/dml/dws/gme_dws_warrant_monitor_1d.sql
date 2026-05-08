-- DML: Daily warrant position monitoring
-- Corresponding DDL: src/ddl/dws/gme_dws_warrant_monitor_1d.sql

WITH latest_spot AS (
    SELECT DISTINCT pull_date, ticker, spot
    FROM {{ ref('gme_dwd_option_contract_di') }}
    WHERE ticker = 'GME'
)
SELECT
    s.pull_date,
    s.ticker,
    s.spot,

    {{ var('warrant_strike') }}                                             AS warrant_strike,
    {{ var('warrant_quantity') }}                                           AS warrant_qty,
    DATE '{{ var("warrant_expiry") }}'                                     AS warrant_expiry,

    (DATE '{{ var("warrant_expiry") }}' - s.pull_date)                     AS dte,
    GREATEST(0, s.spot - {{ var('warrant_strike') }})
        * {{ var('warrant_quantity') }}                                     AS intrinsic_total,
    ROUND((s.spot - {{ var('warrant_strike') }})
        / NULLIF({{ var('warrant_strike') }}, 0) * 100, 2)                 AS moneyness_pct,
    ROUND(({{ var('warrant_strike') }} - s.spot)
        / NULLIF(s.spot, 0) * 100, 2)                                      AS distance_to_strike_pct,

    CASE
        WHEN s.spot >= {{ var('warrant_strike') }} THEN 'ITM'
        WHEN s.spot >= {{ var('warrant_strike') }} * 0.9 THEN 'NEAR_MONEY'
        ELSE 'OTM'
    END                                                                    AS moneyness,
    CASE
        WHEN (DATE '{{ var("warrant_expiry") }}' - s.pull_date) > 120 THEN 'LOW'
        WHEN (DATE '{{ var("warrant_expiry") }}' - s.pull_date) > 60  THEN 'MEDIUM'
        ELSE 'HIGH'
    END                                                                    AS theta_regime,

    s.spot * {{ var('share_quantity') }}                                    AS share_position_value,
    GREATEST(0, s.spot - {{ var('warrant_strike') }})
        * {{ var('warrant_quantity') }}
        + s.spot * {{ var('share_quantity') }}                              AS total_position_value

FROM latest_spot s

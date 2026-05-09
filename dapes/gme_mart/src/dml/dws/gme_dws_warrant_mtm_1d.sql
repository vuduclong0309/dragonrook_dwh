-- DML: Warrant Mark-To-Market (Codex Enhancement #2)
-- Uses CBOE call chain for the matching warrant contract (Oct 2026 $32C)
-- Gives market value, daily P&L, and Greeks for the warrant position
-- Value: exit timing based on actual market pricing, not just intrinsic

WITH warrant_contract AS (
    SELECT
        pull_date,
        ticker,
        spot,
        expiry                                                          AS warrant_expiry,
        strike                                                          AS warrant_strike,
        dte,
        COALESCE(mid_price, theo, last_trade_price)                     AS warrant_mark,
        implied_vol,
        delta,
        theta,
        vega
    FROM {{ ref('gme_dwd_option_contract_di') }}
    WHERE ticker = 'GME'
      AND option_type = 'call'
      AND expiry = DATE '{{ var("warrant_expiry") }}'
      AND strike = {{ var('warrant_strike') }}
)
SELECT
    pull_date,
    ticker,
    spot,
    warrant_strike,
    warrant_expiry,
    dte,
    warrant_mark,
    warrant_mark * {{ var('warrant_quantity') }}                         AS warrant_market_value,
    LAG(warrant_mark * {{ var('warrant_quantity') }})
        OVER (PARTITION BY ticker ORDER BY pull_date)                   AS prior_market_value,
    warrant_mark * {{ var('warrant_quantity') }}
      - COALESCE(LAG(warrant_mark * {{ var('warrant_quantity') }})
        OVER (PARTITION BY ticker ORDER BY pull_date), 0)               AS daily_unrealized_pnl,
    implied_vol,
    delta,
    theta,
    vega,

    -- Position Greeks (scaled by quantity)
    delta * {{ var('warrant_quantity') }}                                AS position_delta,
    theta * {{ var('warrant_quantity') }}                                AS position_theta,
    vega * {{ var('warrant_quantity') }}                                 AS position_vega
FROM warrant_contract

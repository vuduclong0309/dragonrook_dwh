{{
  config(
    materialized='table'
  )
}}

-- DWS: Daily regime classification using ADX(14) + ATR percentile
-- Regime logic [THEORETICAL]:
--   ADX >= 25 AND atr_percentile > 75th → STRONG_TREND
--   ADX >= 25 → TRENDING
--   ADX < 25 AND atr_percentile < 25th → LOW_VOL_RANGE
--   ADX < 25 → RANGING
-- Defaults are operator-confirmable; stored in dbt vars.

WITH bars AS (
    SELECT
        trade_date,
        close,
        high,
        low,
        atr14,
        tr
    FROM {{ ref('xauusd_dwd_bar_di') }}
    WHERE atr14 IS NOT NULL
),
directional_moves AS (
    SELECT
        *,
        high - LAG(high) OVER (ORDER BY trade_date) AS up_move,
        LAG(low) OVER (ORDER BY trade_date) - low   AS down_move
    FROM bars
),
dm AS (
    SELECT
        *,
        CASE WHEN up_move > down_move AND up_move > 0 THEN up_move ELSE 0 END AS plus_dm,
        CASE WHEN down_move > up_move AND down_move > 0 THEN down_move ELSE 0 END AS minus_dm
    FROM directional_moves
),
smoothed AS (
    SELECT
        trade_date,
        close,
        atr14,
        AVG(plus_dm) OVER (
            ORDER BY trade_date
            ROWS BETWEEN {{ var('adx_period') }} - 1 PRECEDING AND CURRENT ROW
        ) AS smoothed_plus_dm,
        AVG(minus_dm) OVER (
            ORDER BY trade_date
            ROWS BETWEEN {{ var('adx_period') }} - 1 PRECEDING AND CURRENT ROW
        ) AS smoothed_minus_dm,
        AVG(tr) OVER (
            ORDER BY trade_date
            ROWS BETWEEN {{ var('adx_period') }} - 1 PRECEDING AND CURRENT ROW
        ) AS smoothed_tr
    FROM dm
),
di AS (
    SELECT
        *,
        CASE WHEN smoothed_tr > 0 THEN (smoothed_plus_dm / smoothed_tr) * 100 ELSE 0 END AS plus_di,
        CASE WHEN smoothed_tr > 0 THEN (smoothed_minus_dm / smoothed_tr) * 100 ELSE 0 END AS minus_di
    FROM smoothed
),
dx AS (
    SELECT
        *,
        CASE
            WHEN (plus_di + minus_di) > 0
            THEN ABS(plus_di - minus_di) / (plus_di + minus_di) * 100
            ELSE 0
        END AS dx_val
    FROM di
),
adx AS (
    SELECT
        trade_date,
        close,
        atr14,
        ROUND(AVG(dx_val) OVER (
            ORDER BY trade_date
            ROWS BETWEEN {{ var('adx_period') }} - 1 PRECEDING AND CURRENT ROW
        ), 2) AS adx14
    FROM dx
),
with_percentile AS (
    SELECT
        trade_date,
        close,
        atr14,
        adx14,
        ROUND(PERCENT_RANK() OVER (
            ORDER BY atr14
            ROWS BETWEEN 59 PRECEDING AND CURRENT ROW
        ) * 100, 2) AS atr_percentile_60d
    FROM adx
)
SELECT
    trade_date,
    close,
    atr14,
    adx14,
    atr_percentile_60d,
    CASE
        WHEN adx14 >= {{ var('adx_trend_threshold') }} AND atr_percentile_60d > {{ var('atr_percentile_range_high') }}
            THEN 'STRONG_TREND'
        WHEN adx14 >= {{ var('adx_trend_threshold') }}
            THEN 'TRENDING'
        WHEN adx14 < {{ var('adx_trend_threshold') }} AND atr_percentile_60d < {{ var('atr_percentile_range_low') }}
            THEN 'LOW_VOL_RANGE'
        ELSE 'RANGING'
    END AS regime
FROM with_percentile

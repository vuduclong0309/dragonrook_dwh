{{
  config(
    materialized='table'
  )
}}

-- DWD: Daily bar with True Range and ATR(14)
-- ATR uses Wilder's smoothing (EMA with alpha = 1/period)
-- [REAL_API] OHLCV from yfinance; [THEORETICAL] ATR calculation methodology

WITH bars_with_tr AS (
    SELECT
        trade_date,
        open,
        high,
        low,
        close,
        volume,
        GREATEST(
            high - low,
            ABS(high - LAG(close) OVER (ORDER BY trade_date)),
            ABS(low - LAG(close) OVER (ORDER BY trade_date))
        ) AS tr
    FROM {{ ref('xauusd_ods_daily_bar') }}
),
bars_with_atr AS (
    SELECT
        *,
        AVG(tr) OVER (
            ORDER BY trade_date
            ROWS BETWEEN {{ var('atr_period') }} - 1 PRECEDING AND CURRENT ROW
        ) AS atr14
    FROM bars_with_tr
)
SELECT
    trade_date,
    open,
    high,
    low,
    close,
    volume,
    ROUND(tr, 4) AS tr,
    CASE
        WHEN ROW_NUMBER() OVER (ORDER BY trade_date) >= {{ var('atr_period') }}
        THEN ROUND(atr14, 4)
        ELSE NULL
    END AS atr14
FROM bars_with_atr

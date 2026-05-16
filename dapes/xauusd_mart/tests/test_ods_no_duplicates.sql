-- Verify no duplicate trade_dates in ODS
SELECT
    trade_date,
    COUNT(*) AS cnt
FROM {{ ref('xauusd_ods_daily_bar') }}
GROUP BY trade_date
HAVING COUNT(*) > 1

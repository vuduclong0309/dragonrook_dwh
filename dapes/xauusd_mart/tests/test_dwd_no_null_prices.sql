-- Verify no NULL OHLC prices in DWD bar model
SELECT
    trade_date,
    open,
    high,
    low,
    close
FROM {{ ref('xauusd_dwd_bar_di') }}
WHERE open IS NULL
   OR high IS NULL
   OR low IS NULL
   OR close IS NULL

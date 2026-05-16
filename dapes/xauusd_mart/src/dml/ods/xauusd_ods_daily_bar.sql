{{
  config(
    materialized='incremental',
    unique_key='trade_date'
  )
}}

-- ODS: Select from pre-loaded raw table (populated by ingest_xauusd.py)
-- Source: yfinance GC=F (COMEX gold futures continuous front-month) [REAL_API]
-- Unlike gme_mart which pulls via httpfs in-model, XAUUSD uses a Python
-- pre-ingestion step because yfinance has no stable HTTP/JSON endpoint
-- that DuckDB's read_json_auto can consume directly.

SELECT
    trade_date,
    ticker,
    provider,
    source_symbol,
    open,
    high,
    low,
    close,
    volume,
    pull_ts_utc
FROM {{ source('raw', 'xauusd_ods_daily_bar') }}

{% if is_incremental() %}
WHERE trade_date >= (SELECT MAX(trade_date) FROM {{ this }})
{% endif %}

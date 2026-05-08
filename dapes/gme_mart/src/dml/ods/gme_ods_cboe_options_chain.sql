{{
  config(
    materialized='incremental',
    unique_key=['pull_date', 'option_symbol']
  )
}}

-- DML: Ingest CBOE delayed options chain via MotherDuck httpfs
-- Corresponding DDL: src/ddl/ods/gme_ods_cboe_options_chain.sql
-- Source: cdn.cboe.com/api/global/delayed_quotes/options/GME.json

WITH raw_unnested AS (
    SELECT
        unnest(data.options) AS elem,
        data.close AS underlying_close,
        "timestamp" AS cboe_timestamp
    FROM read_json_auto(
        'https://cdn.cboe.com/api/global/delayed_quotes/options/GME.json',
        maximum_object_size=10485760
    )
),
parsed AS (
    SELECT
        CURRENT_DATE                                           AS pull_date,
        'GME'                                                  AS ticker,
        'cboe'                                                 AS provider,
        NOW()                                                  AS pull_ts_utc,

        -- Raw CBOE fields
        CAST(elem['option'] AS VARCHAR)                        AS option_symbol,
        CAST(elem['bid'] AS DOUBLE)                            AS bid,
        CAST(elem['bid_size'] AS INTEGER)                      AS bid_size,
        CAST(elem['ask'] AS DOUBLE)                            AS ask,
        CAST(elem['ask_size'] AS INTEGER)                      AS ask_size,
        CAST(elem['iv'] AS DOUBLE)                             AS iv,
        CAST(elem['open_interest'] AS INTEGER)                 AS open_interest,
        CAST(elem['volume'] AS INTEGER)                        AS volume,
        CAST(elem['delta'] AS DOUBLE)                          AS delta,
        CAST(elem['gamma'] AS DOUBLE)                          AS gamma,
        CAST(elem['theta'] AS DOUBLE)                          AS theta,
        CAST(elem['vega'] AS DOUBLE)                           AS vega,
        CAST(elem['rho'] AS DOUBLE)                            AS rho,
        CAST(elem['theo'] AS DOUBLE)                           AS theo,
        CAST(elem['change'] AS DOUBLE)                         AS change,
        CAST(elem['open'] AS DOUBLE)                           AS opt_open,
        CAST(elem['high'] AS DOUBLE)                           AS opt_high,
        CAST(elem['low'] AS DOUBLE)                            AS opt_low,
        CAST(elem['tick'] AS VARCHAR)                          AS tick,
        CAST(elem['last_trade_price'] AS DOUBLE)               AS last_trade_price,
        CAST(elem['last_trade_time'] AS VARCHAR)               AS last_trade_time,
        CAST(elem['percent_change'] AS DOUBLE)                 AS percent_change,
        CAST(elem['prev_day_close'] AS DOUBLE)                 AS prev_day_close,

        underlying_close,
        cboe_timestamp

    FROM raw_unnested
    WHERE elem['option'] IS NOT NULL
)
SELECT
    p.*,
    -- Parse OCC symbol: {ROOT}{YYMMDD}{C/P}{00000000}
    -- GME symbols are 18 chars: GME + 6date + 1type + 8strike
    -- Non-standard symbols (adjusted, minis) may differ — filter on length
    CASE
        WHEN LENGTH(p.option_symbol) = 18 THEN
            TRY_CAST('20' || SUBSTRING(p.option_symbol, 4, 2) || '-'
                || SUBSTRING(p.option_symbol, 6, 2) || '-'
                || SUBSTRING(p.option_symbol, 8, 2) AS DATE)
        ELSE NULL
    END                                                        AS expiry,
    CASE
        WHEN LENGTH(p.option_symbol) = 18 AND SUBSTRING(p.option_symbol, 10, 1) = 'C' THEN 'call'
            WHEN LENGTH(p.option_symbol) = 18 AND SUBSTRING(p.option_symbol, 10, 1) = 'P' THEN 'put'
        ELSE NULL
    END                                                        AS option_type,
    CASE
        WHEN LENGTH(p.option_symbol) = 18 THEN
            TRY_CAST(SUBSTRING(p.option_symbol, 11) AS DOUBLE) / 1000.0
        ELSE NULL
    END                                                        AS strike

FROM parsed p

{% if is_incremental() %}
WHERE p.pull_date >= (SELECT MAX(pull_date) FROM {{ this }})
{% endif %}

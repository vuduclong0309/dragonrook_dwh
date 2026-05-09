-- DML: Cleaned daily option contract facts
-- Corresponding DDL: src/ddl/dwd/gme_dwd_option_contract_di.sql
-- Filters: OI > 0, valid parsed symbols (expiry NOT NULL), non-weekly (DTE >= 7)

SELECT
    ods.pull_date,
    ods.ticker,
    ods.expiry,
    ods.strike,
    ods.option_type,
    ods.option_symbol,

    ods.bid,
    ods.ask,
    CASE WHEN ods.bid > 0 AND ods.ask > 0
         THEN (ods.bid + ods.ask) / 2.0
         ELSE ods.last_trade_price
    END                                                AS mid_price,
    ods.last_trade_price,

    COALESCE(ods.volume, 0)                            AS volume,
    COALESCE(ods.open_interest, 0)                     AS open_interest,

    -- Greeks (REAL from CBOE, not BS-calculated)
    ods.iv                                             AS implied_vol,
    ods.delta,
    ods.gamma,
    ods.theta,
    ods.vega,
    ods.rho,
    ods.theo,

    (ods.expiry - ods.pull_date)                       AS dte,
    ods.underlying_close                               AS spot,

    -- GEX via macro (single source of truth)
    {{ gex_contribution('ods.gamma', 'ods.open_interest', 'ods.underlying_close', 'ods.option_type') }}
                                                       AS gex_contribution,

    CASE
        WHEN ods.expiry = DATE '{{ var("warrant_expiry") }}' THEN 'WARRANT'
        WHEN (ods.expiry - ods.pull_date) > 365        THEN 'LEAP'
        ELSE 'MONTHLY'
    END                                                AS series_type,
    -- Note: WEEKLY case removed — DTE < 7 already filtered in WHERE clause

    ods.provider,
    ods.pull_ts_utc,
    ods.cboe_timestamp

FROM {{ ref('gme_ods_cboe_options_chain') }} ods
WHERE ods.expiry IS NOT NULL          -- filter out unparseable OCC symbols
  AND ods.open_interest > 0
  AND ods.strike IS NOT NULL
  AND ods.underlying_close IS NOT NULL  -- Codex fix: prevent NULL GEX propagation
  AND (ods.expiry - ods.pull_date) > 7   -- exclude weeklies (DTE <= 7)

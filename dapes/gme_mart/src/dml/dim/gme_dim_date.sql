-- DML: Date dimension with role-playing support
-- Adapted from Shopee Star-Schema slides: role-playing dimension pattern
-- Same dim_date table used as BOTH trade_date FK and expiry_date FK
-- Enriched with holidays + macro events from seeds
--
-- Usage in fact tables:
--   JOIN gme_dim_date AS trade_date ON fact.pull_date = trade_date.date_key
--   JOIN gme_dim_date AS expiry_date ON fact.expiry = expiry_date.date_key

WITH date_spine AS (
    -- Generate all dates 2025-01-01 to 2027-12-31
    SELECT UNNEST(generate_series(DATE '2025-01-01', DATE '2027-12-31', INTERVAL 1 DAY))::DATE AS date_key
),
holidays AS (
    SELECT
        CAST(holiday_date AS DATE) AS holiday_date,
        holiday_name,
        early_close
    FROM {{ ref('holidays_nyse_2025_2027') }}
),
events AS (
    SELECT
        CAST(event_date AS DATE) AS event_date,
        event_type,
        event_name,
        impact
    FROM {{ ref('macro_events_2025_2027') }}
)
SELECT
    d.date_key,
    EXTRACT(ISODOW FROM d.date_key) - 1                                AS dow,  -- 0=Mon, 6=Sun
    CASE
        WHEN EXTRACT(ISODOW FROM d.date_key) IN (6, 7) THEN FALSE
        WHEN h.holiday_date IS NOT NULL AND COALESCE(h.early_close, FALSE) = FALSE THEN FALSE
        ELSE TRUE
    END                                                                 AS is_trading_day,
    h.holiday_date IS NOT NULL                                          AS is_holiday,
    COALESCE(h.early_close, FALSE)                                      AS is_early_close,
    h.holiday_name,

    -- Macro events (role-playable: "is there an event on my trade date?" OR "on my expiry date?")
    MAX(CASE WHEN e.event_type = 'FOMC' THEN TRUE ELSE FALSE END)       AS has_fomc,
    MAX(CASE WHEN e.event_type = 'NFP' THEN TRUE ELSE FALSE END)        AS has_nfp,
    MAX(CASE WHEN e.event_type = 'CPI' THEN TRUE ELSE FALSE END)        AS has_cpi,
    MAX(CASE WHEN e.event_type = 'GME_ER' THEN TRUE ELSE FALSE END)     AS has_earnings,

    EXTRACT(WEEK FROM d.date_key)                                       AS week_of_year,
    EXTRACT(MONTH FROM d.date_key)                                      AS month,
    EXTRACT(QUARTER FROM d.date_key)                                    AS quarter,
    EXTRACT(YEAR FROM d.date_key)                                       AS year

FROM date_spine d
LEFT JOIN holidays h ON d.date_key = h.holiday_date
LEFT JOIN events e ON d.date_key = e.event_date
GROUP BY d.date_key, h.holiday_date, h.holiday_name, h.early_close

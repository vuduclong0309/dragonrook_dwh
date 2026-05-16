-- Dim date for XAUUSD mart. Reuses same holiday/event seeds as gme_mart.
-- Uses NYSE calendar as proxy for COMEX (v1 simplification — COMEX closes
-- on same federal holidays; minor differences like Good Friday are accepted).

WITH date_spine AS (
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
    EXTRACT(ISODOW FROM d.date_key) - 1                                AS dow,
    CASE
        WHEN EXTRACT(ISODOW FROM d.date_key) IN (6, 7) THEN FALSE
        WHEN h.holiday_date IS NOT NULL AND COALESCE(h.early_close, FALSE) = FALSE THEN FALSE
        ELSE TRUE
    END                                                                 AS is_trading_day,
    h.holiday_date IS NOT NULL                                          AS is_holiday,
    COALESCE(h.early_close, FALSE)                                      AS is_early_close,
    h.holiday_name,

    MAX(CASE WHEN e.event_type = 'FOMC' THEN TRUE ELSE FALSE END)       AS has_fomc,
    MAX(CASE WHEN e.event_type = 'NFP' THEN TRUE ELSE FALSE END)        AS has_nfp,
    MAX(CASE WHEN e.event_type = 'CPI' THEN TRUE ELSE FALSE END)        AS has_cpi,

    EXTRACT(WEEK FROM d.date_key)                                       AS week_of_year,
    EXTRACT(MONTH FROM d.date_key)                                      AS month,
    EXTRACT(QUARTER FROM d.date_key)                                    AS quarter,
    EXTRACT(YEAR FROM d.date_key)                                       AS year

FROM date_spine d
LEFT JOIN holidays h ON d.date_key = h.holiday_date
LEFT JOIN events e ON d.date_key = e.event_date
GROUP BY d.date_key, h.holiday_date, h.holiday_name, h.early_close

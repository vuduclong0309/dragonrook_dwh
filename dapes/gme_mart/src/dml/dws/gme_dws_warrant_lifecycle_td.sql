-- DML: Accumulating Snapshot — Warrant Lifecycle (Deep Mine Action #6)
-- Adapted from Shopee Star-Schema slides: accumulating snapshot pattern
-- Tracks warrant position from first observation to expiry
-- _td = to-date (cumulative, growing daily)
--
-- Key milestones tracked:
-- - First observed date + spot
-- - ATM date (first time spot >= strike)
-- - ITM date (first time spot >= strike * 1.05)
-- - Peak spot + date
-- - Min spot + date (deepest OTM)
-- - Current state

WITH daily AS (
    SELECT
        pull_date,
        spot,
        warrant_strike,
        warrant_expiry,
        dte,
        intrinsic_total,
        moneyness,
        theta_regime
    FROM {{ ref('gme_dws_warrant_monitor_1d') }}
),
milestones AS (
    SELECT
        MIN(pull_date)                                                  AS first_observed_date,
        MIN(spot)                                                       AS min_spot,
        MAX(spot)                                                       AS max_spot,
        (SELECT pull_date FROM daily ORDER BY spot DESC LIMIT 1)        AS peak_spot_date,
        (SELECT pull_date FROM daily ORDER BY spot ASC LIMIT 1)         AS trough_spot_date,
        MIN(CASE WHEN spot >= warrant_strike THEN pull_date END)        AS first_atm_date,
        MIN(CASE WHEN spot >= warrant_strike * 1.05 THEN pull_date END) AS first_itm_date,
        COUNT(*)                                                        AS total_observations
    FROM daily
)
SELECT
    d.pull_date,
    d.spot,
    d.warrant_strike,
    d.warrant_expiry,
    d.dte,
    d.intrinsic_total,
    d.moneyness,
    d.theta_regime,

    -- Lifecycle milestones (accumulating — filled once, never unfilled)
    m.first_observed_date,
    m.first_atm_date,
    m.first_itm_date,
    m.peak_spot_date,
    m.max_spot                                                          AS peak_spot,
    m.trough_spot_date,
    m.min_spot                                                          AS trough_spot,

    -- Position metrics over full history
    m.total_observations,
    d.spot - m.min_spot                                                 AS recovery_from_trough,
    m.max_spot - d.spot                                                 AS drawdown_from_peak,
    ROUND((d.spot - m.min_spot) / NULLIF(m.max_spot - m.min_spot, 0) * 100, 1)
                                                                        AS range_position_pct,

    -- Warrant time value decay tracking
    ROUND((d.warrant_expiry - d.pull_date) * 1.0
        / NULLIF(d.warrant_expiry - m.first_observed_date, 0) * 100, 1)
                                                                        AS time_remaining_pct

FROM daily d
CROSS JOIN milestones m
WHERE d.pull_date = (SELECT MAX(pull_date) FROM daily)

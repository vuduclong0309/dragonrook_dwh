-- DML: OBT (One Big Table) for Warrant Dashboard (Deep Mine Action #7)
-- Adapted from Shopee daas-batch-pipelines wide denormalized pattern
-- Single query = everything needed for the dapes-briefing MCP skill
-- LEFT JOINs all DWS models into one consumption-ready view

SELECT
    -- Core
    snap.pull_date,
    snap.ticker,
    snap.spot,

    -- Max Pain
    snap.max_pain_strike,
    snap.max_pain_convergence_pct,

    -- GEX
    snap.net_gex,
    snap.top_gex_strike,
    trend.gex_regime,
    trend.net_gex_avg_5d,
    trend.net_gex_delta_1d,
    trend.spot_delta_1d,

    -- GEX Alert
    alert.alert_type                                        AS gex_alert,

    -- P/C & OI
    snap.pc_ratio,
    snap.top_oi_strike_1,
    snap.top_oi_strike_2,
    snap.top_oi_strike_3,

    -- Warrant Monitor (intrinsic)
    wm.warrant_strike,
    wm.warrant_qty,
    wm.dte                                                  AS warrant_dte,
    wm.intrinsic_total,
    wm.moneyness,
    wm.theta_regime,
    wm.distance_to_strike_pct,
    wm.share_position_value,
    wm.total_position_value,

    -- Warrant MTM (market value)
    mtm.warrant_mark,
    mtm.warrant_market_value,
    mtm.daily_unrealized_pnl,
    mtm.implied_vol                                         AS warrant_iv,
    mtm.position_delta,
    mtm.position_theta,
    mtm.position_vega,

    -- IV Regime (Phase 1.5)
    iv.iv_atm,
    iv.iv_percentile_all,
    iv.iv_regime,
    iv.history_days                                          AS iv_history_days,

    -- Flow Signals
    flow.unusual_flow_count,
    flow.position_build_count,
    flow.top_build_strike,
    flow.flow_signal,
    flow.volume_call_put_ratio,

    -- Warrant Lifecycle (accumulating snapshot)
    lc.peak_spot,
    lc.trough_spot,
    lc.recovery_from_trough,
    lc.drawdown_from_peak,
    lc.range_position_pct,
    lc.time_remaining_pct

FROM {{ ref('gme_dws_daily_snapshot_1d') }} snap
LEFT JOIN {{ ref('gme_dws_gex_trend_nd') }} trend
    ON snap.pull_date = trend.pull_date AND snap.ticker = trend.ticker
LEFT JOIN {{ ref('gme_dws_gex_flip_alert_1d') }} alert
    ON snap.pull_date = alert.pull_date AND snap.ticker = alert.ticker
LEFT JOIN {{ ref('gme_dws_warrant_monitor_1d') }} wm
    ON snap.pull_date = wm.pull_date
LEFT JOIN {{ ref('gme_dws_warrant_mtm_1d') }} mtm
    ON snap.pull_date = mtm.pull_date AND snap.ticker = mtm.ticker
LEFT JOIN {{ ref('gme_dws_iv_percentile_1d') }} iv
    ON snap.pull_date = iv.pull_date AND snap.ticker = iv.ticker
LEFT JOIN {{ ref('gme_dws_unusual_flow_summary_1d') }} flow
    ON snap.pull_date = flow.pull_date AND snap.ticker = flow.ticker
LEFT JOIN {{ ref('gme_dws_warrant_lifecycle_td') }} lc
    ON snap.pull_date = lc.pull_date

-- DDL: gme_dws_daily_snapshot_1d
-- Daily summary for briefing skill

CREATE TABLE IF NOT EXISTS gme_dws_daily_snapshot_1d (
    pull_date                   DATE          NOT NULL,
    ticker                      VARCHAR       NOT NULL,
    spot                        DOUBLE,
    max_pain_strike             DOUBLE,
    max_pain_convergence_pct    DOUBLE,
    net_gex                     DOUBLE,
    top_gex_strike              DOUBLE,
    pc_ratio                    DOUBLE,
    top_oi_strike_1             DOUBLE,
    top_oi_strike_2             DOUBLE,
    top_oi_strike_3             DOUBLE,

    PRIMARY KEY (pull_date, ticker)
);

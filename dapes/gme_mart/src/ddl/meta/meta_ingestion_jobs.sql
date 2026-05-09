-- DDL: meta_ingestion_jobs
-- Pipeline observability table (adapted from Shopee Automatic DB Ingestion)
-- Tracks each ingestion run: status, row count, duration, errors

CREATE TABLE IF NOT EXISTS meta_ingestion_jobs (
    job_id              VARCHAR       PRIMARY KEY,
    source_name         VARCHAR       NOT NULL,     -- 'cboe_httpfs', 'yfinance', 'manual_seed'
    target_table        VARCHAR       NOT NULL,     -- 'gme_ods_cboe_options_chain'
    run_date            DATE          NOT NULL,
    started_at          TIMESTAMP,
    completed_at        TIMESTAMP,
    run_status          VARCHAR,                    -- 'SUCCESS', 'FAILED', 'RUNNING', 'SKIPPED'
    rows_ingested       BIGINT        DEFAULT 0,
    run_duration_sec    INTEGER,
    error_message       VARCHAR,
    config_json         VARCHAR,                    -- ingestion parameters
    triggered_by        VARCHAR       DEFAULT 'github_actions'  -- 'github_actions', 'manual', 'cron'
);

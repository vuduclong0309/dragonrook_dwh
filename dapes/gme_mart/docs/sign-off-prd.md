# GME Options Mart -- Sign-Off PRD

| Field | Value |
|-------|-------|
| **Mart** | `gme-mart` |
| **Version** | 3.1 |
| **PRD Contract** | WS-1 (operator-waived, grade B) |
| **Date** | 2026-05-21 |
| **Framework** | mart-forge v1.0 |

---

## 1. Business Purpose

Monitor GME listed-options activity to support warrant-informed trading decisions. The mart consolidates CBOE options-chain snapshots into a Kimball-modeled warehouse that surfaces daily GEX (Gamma Exposure), max-pain, put/call ratios, IV percentiles, and flow-pressure signals. A dedicated warrant-monitor layer tracks proximity of the underlying to the publicly disclosed SEC warrant terms ($32 strike, October 2026 expiry) so the operator can assess dilution risk and hedging opportunities without manual spreadsheet work.

**Out of scope:** Portfolio position sizes, account balances, order quantities, or any non-public trading information.

---

## 2. Source Systems

| Source | Role | Protocol | Auth |
|--------|------|----------|------|
| **CBOE** | Primary | httpfs (delayed options chain CSV) | None (public) |
| **yfinance** | Fallback | Python SDK (spot price, historical) | None (public) |

Both sources provide publicly available market data. No paid or licensed data feeds are used.

---

## 3. Grain

**Declared grain:** one row per option contract per trading day.

The atomic fact table `gme_dwd_option_contract_di` stores one record for each unique combination of `(pull_date, expiration, strike, option_type)`. All summary tables aggregate from this grain upward.

---

## 4. Dimensions, Facts, and Bus Matrix

### 4.1 Dimensions

| Dimension | Scope | Key | Description |
|-----------|-------|-----|-------------|
| `gme_dim_date` | Conformed | `date_key` | Trading-calendar dimension with holidays, expiry flags |
| `dim_ticker` | Local | `ticker` | Single-ticker (GME); exists for framework conformance |

### 4.2 Facts and Summaries

| Layer | Model | Grain | Description |
|-------|-------|-------|-------------|
| ODS | `gme_ods_cboe_options_chain` | per-contract-per-day | Raw CBOE snapshot, append-only |
| DWD | `gme_dwd_option_contract_di` | per-contract-per-day | Enriched fact: Greeks, moneyness, GEX contribution |
| DWS | `gme_dws_strike_gex_1d` | per-strike-per-day | GEX aggregated by strike price |
| DWS | `gme_dws_daily_snapshot_1d` | per-day | Daily max-pain, P/C ratio, total GEX, spot |
| DWS | `gme_dws_gex_trend_nd` | per-day (rolling) | Multi-day GEX trend and regime classification |
| DWS | `gme_dws_gex_flip_alert_1d` | per-day | GEX sign-flip detection and alerts |
| DWS | `gme_dws_flow_pressure_1d` | per-day | Net flow pressure (call vs put volume) |
| DWS | `gme_dws_iv_percentile_1d` | per-day | IV rank and percentile vs trailing history |
| DWS | `gme_dws_unusual_flow_summary_1d` | per-day | Unusual volume/OI flags |
| DWS | `gme_dws_warrant_monitor_1d` | per-day | Warrant-strike proximity and moneyness |
| DWS | `gme_dws_warrant_lifecycle_td` | to-date | Warrant lifecycle tracking (time to expiry) |
| DWS | `gme_dws_warrant_mtm_1d` | per-day | Warrant mark-to-market vs $32 strike [THEORETICAL] |
| ADS | `gme_ads_warrant_dashboard` | per-day | Pre-joined dashboard view for operator consumption |
| META | `meta_ingestion_jobs` | per-run | Pipeline run metadata and audit trail |

### 4.3 Bus Matrix

| Fact / Summary | dim_date | dim_ticker |
|----------------|:--------:|:----------:|
| `gme_dwd_option_contract_di` | X | X |
| `gme_dws_strike_gex_1d` | X | X |
| `gme_dws_daily_snapshot_1d` | X | X |
| `gme_dws_gex_trend_nd` | X | X |
| `gme_dws_gex_flip_alert_1d` | X | X |
| `gme_dws_flow_pressure_1d` | X | X |
| `gme_dws_iv_percentile_1d` | X | X |
| `gme_dws_unusual_flow_summary_1d` | X | X |
| `gme_dws_warrant_monitor_1d` | X | X |
| `gme_dws_warrant_lifecycle_td` | X | X |
| `gme_dws_warrant_mtm_1d` | X | X |
| `gme_ads_warrant_dashboard` | X | X |

---

## 5. Refresh Cadence

| Parameter | Value |
|-----------|-------|
| **Cron** | `45 20 * * 1-5` |
| **Timezone** | America/New_York |
| **Meaning** | 8:45 PM ET, Monday--Friday (post-market close) |
| **Skip holidays** | Yes (NYSE calendar) |
| **Pipeline steps** | seed, run, test |
| **Fail-fast** | Yes |
| **Timeout** | 10 minutes |

---

## 6. Data Quality Controls

8 controls from the DQC scorecard (`dqc_scorecard.json`, generated 2026-05-16).

| # | Control Class | Status | Models Covered | Implementation |
|---|--------------|--------|----------------|----------------|
| 1 | **pk_integrity** | PASS | dim_date, ods, dwd, dws_strike_gex, dws_daily_snapshot, ads_warrant_dashboard | `schema.yml` not_null + unique tests on date_key, pull_date, composite PK columns |
| 2 | **fk_integrity** | PASS | dwd_option_contract_di | Implicit via incremental joins on dim_date; orphan rows impossible by construction |
| 3 | **freshness** | PASS | ods_cboe_options_chain | dbt source freshness: warn 36 h, error 72 h on `pull_date` |
| 4 | **completeness_volume** | PASS | ods, dwd | `test_ods_row_count.sql` asserts >= 100 rows per pull_date |
| 5 | **accepted_ranges** | PASS | dwd, dws_gex_trend, dws_gex_flip_alert, dws_flow_pressure | accepted_values on option_type, series_type, gex_regime, alert_type, flow_pressure_label; `test_spot_range.sql` validates spot 1--500 |
| 6 | **duplicate_detection** | PASS | ods, dwd | `test_ods_no_duplicates.sql`, `test_dwd_no_duplicates.sql` |
| 7 | **null_rate_threshold** | PASS | dwd | `test_dwd_no_null_greeks.sql` validates gamma/delta/iv not null where OI > 0 |
| 8 | **business_reconciliation** | PASS (with waiver) | cross-mart | See reconciliation detail below |

### 6.1 Reconciliation Detail

| Metric | External Source | Tolerance | Status | Notes |
|--------|----------------|-----------|--------|-------|
| max_pain | swaggystocks | 5% | PASS | Validated within $1 of swaggystocks.com display [REAL_API] |
| pc_ratio | barchart | 0.02 | PASS | Validated within 0.02 of Barchart P/C ratio [REAL_API] |
| net_gex | (none available) | n/a | UNAVAILABLE | No free external GEX source exists. Paywalled sources (SpotGamma, Volland) are out of budget. GEX formula verified via Python reference implementation [PYTHON_SIM]. **Operator waiver granted 2026-05-08.** |

---

## 7. Sign-Off

### Approval Record

| Role | Name | Date | Decision |
|------|------|------|----------|
| **Data Owner / Operator** | *(operator)* | *(pending)* | *(pending)* |
| **Data Consumer / Stakeholder** | *(operator, solo-operator exception)* | *(pending)* | *(pending)* |

**Solo-operator exception:** This mart is operated and consumed by a single person. Per the mart-forge framework, the operator self-signs both the Data Owner and Data Consumer lines. No additional stakeholder sign-off is required.

### Sign-Off Checklist

- [ ] All 8 DQC controls reviewed (7 pass, 1 waived with documented rationale)
- [ ] Bus matrix matches implemented models
- [ ] Refresh schedule confirmed operational
- [ ] No confidential data exposed (no position sizes, account balances, or order quantities)
- [ ] Reconciliation waivers have documented justification and approval date
- [ ] Pipeline timeout and fail-fast settings are appropriate for data volume

### Waivers in Effect

| Control | Waiver Reason | Approved By | Date |
|---------|---------------|-------------|------|
| net_gex reconciliation | No free external GEX benchmark exists; formula verified via Python reference impl [PYTHON_SIM] | operator | 2026-05-08 |

---

*Generated for mart-forge v1.0. Source artifacts: `mart.yml` v3.1, `dqc_scorecard.json` 2026-05-16.*

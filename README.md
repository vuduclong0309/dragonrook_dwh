# DragonRook DWH

Kimball-style data warehouse on [MotherDuck](https://motherduck.com/) (cloud DuckDB). Options analytics for GME warrants + equity positions. Built with dbt-duckdb, scheduled via GitHub Actions.

**Architecture:** Adapted from Shopee's production data marts (DE101 Kimball methodology). DDL/DML separation, multi-tier DQC, Kimball bus matrix.

## How to Read This Project

1. **Start with [`bi_req/`](bi_req/)** for the business problem — why monitor GME options via a DWH, and what decisions the data informs
2. **Read [`dapes/gme_mart/docs/`](dapes/gme_mart/docs/)** for methodology — Kimball patterns, bus matrix, DQC framework
3. **Explore [`dapes/`](dapes/)** for implementation — GME mart (options analytics) and XAUUSD mart (regime classification)

## GME Mart — First Mart

Real-time GME options analytics: GEX (Gamma Exposure), max pain, warrant monitoring, flow pressure detection.

**Data source:** CBOE delayed options chain via MotherDuck httpfs — all Greeks (gamma, delta, theta, vega, rho, IV) from a single `read_json_auto()` call. No API keys. No Python ingestion layer. Pure SQL.

### Model Inventory (14 models)

| Layer | Model | Purpose |
|---|---|---|
| **DIM** | `gme_dim_date` | Trading calendar with holidays + macro events. Role-playing (trade_date / expiry_date) |
| **ODS** | `gme_ods_cboe_options_chain` | Raw CBOE chain via httpfs. Incremental append-only |
| **DWD** | `gme_dwd_option_contract_di` | Cleaned facts. GEX contribution per contract. Series classification |
| **DWS** | `gme_dws_strike_gex_1d` | Net GEX by strike, ranked |
| | `gme_dws_warrant_monitor_1d` | Intrinsic, moneyness, DTE, theta regime |
| | `gme_dws_daily_snapshot_1d` | Spot, max pain (per-expiry), P/C ratio, top OI |
| | `gme_dws_gex_trend_nd` | 5-day rolling regime (POSITIVE_EXPANDING / STABLE / NEGATIVE) |
| | `gme_dws_gex_flip_alert_1d` | Regime transition detection |
| | `gme_dws_warrant_mtm_1d` | Market value from CBOE call chain + position Greeks |
| | `gme_dws_flow_pressure_1d` | Unusual activity proxy (volume/OI analysis) |
| | `gme_dws_unusual_flow_summary_1d` | Aggregate flow signals |
| | `gme_dws_warrant_lifecycle_td` | Accumulating snapshot (first ATM, peak, trough) |
| **ADS** | `gme_ads_warrant_dashboard` | One Big Table for consumption (single query = full briefing) |
| **Meta** | `meta_ingestion_jobs` | Pipeline observability |

### DQC (Data Quality Checks)

30+ dbt tests: not_null on PKs, accepted_values on enums, duplicate detection, row count baseline, null rate checks, spot range validation.

**Validated against external sources:**
- Max pain: $24.00 = swaggystocks/maximum-pain.com
- P/C ratio: 0.33 = Barchart
- Top OI strikes: $30/$25/$50 = consistent

## XAUUSD Mart — Second Mart

Daily gold/XAUUSD analytics for FHAegis (FHAG) pillar. Regime classification (trending vs ranging) via ADX + ATR percentile.

**Data source:** Yahoo Finance (`GC=F` COMEX gold futures) via Python `yfinance` ingestion → MotherDuck. Daily bars only (v1).

### Model Inventory (4 models)

| Layer | Model | Purpose |
|---|---|---|
| **DIM** | `xauusd_dim_date` | Trading calendar (NYSE as COMEX proxy) |
| **ODS** | `xauusd_ods_daily_bar` | Raw daily OHLCV from yfinance. Incremental |
| **DWD** | `xauusd_dwd_bar_di` | Cleaned bar + True Range + ATR(14) |
| **DWS** | `xauusd_dws_regime_1d` | ADX(14) + ATR percentile → regime label |

### Regime Labels [THEORETICAL]

| Regime | Condition |
|---|---|
| `STRONG_TREND` | ADX >= 25 AND ATR percentile > 75th |
| `TRENDING` | ADX >= 25 |
| `LOW_VOL_RANGE` | ADX < 25 AND ATR percentile < 25th |
| `RANGING` | ADX < 25 |

**Schedule:** GitHub Actions cron `0 19 * * 1-5` (15:00 ET, after COMEX close)

## Architecture

```
CBOE Cloud (free, delayed 15min)
    |
    | cdn.cboe.com/api/global/delayed_quotes/options/GME.json
    v
MotherDuck httpfs (read_json_auto)
    |
    v
+--[gme_db on MotherDuck]--+
|                           |
|  ODS (raw, append-only)   |
|    |                      |
|  DIM (date, holidays)     |
|    |                      |
|  DWD (cleaned facts)      |
|    |                      |
|  DWS (aggregations x8)   |
|    |                      |
|  ADS (OBT dashboard)     |
+---------------------------+
    |
    v
MCP Skill (dapes-briefing)
```

**Pipeline:** `DDL` -> `dbt seed` -> `dbt run` -> `dbt test` -> `dbt docs generate`
**Schedule:** GitHub Actions cron `45 20 * * 1-5` (16:45 ET, weekdays)
**Runtime:** ~45 seconds end-to-end

## Structure

```
dragonrook_dwh/
├── dapes/                          # Project scope
│   ├── gme_mart/                   # First mart (GME options)
│       ├── src/
│       │   ├── ddl/                # CREATE TABLE (explicit schemas)
│       │   │   ├── ods/
│       │   │   ├── dim/
│       │   │   ├── dwd/
│       │   │   ├── dws/
│       │   │   └── meta/
│       │   ├── dml/                # dbt models (transforms)
│       │   │   ├── ods/
│       │   │   ├── dim/
│       │   │   ├── dwd/
│       │   │   └── dws/
│       │   └── resource/           # Utilities (DDL runner, DQC scripts)
│       ├── seeds/                  # Holidays, macro events (2025-2027)
│       ├── tests/                  # Singular DQC tests
│       ├── docs/                   # Shopee DE patterns (~2600 lines)
│       ├── dbt_project.yml
│       └── profiles.yml
│   └── xauusd_mart/                # Second mart (XAUUSD regime)
│       ├── src/
│       │   ├── ddl/                # CREATE TABLE schemas
│       │   ├── dml/                # dbt models (ods/dim/dwd/dws)
│       │   └── resource/           # Ingestion + DDL runner
│       ├── seeds/                  # Shared holiday/event CSVs
│       ├── tests/                  # DQC tests
│       ├── dbt_project.yml
│       ���── profiles.yml
├── shared/                         # Conformed dimensions (future)
├── .github/workflows/
│   ├── gme-mart-daily.yml
│   └── xauusd-mart-daily.yml
└── README.md
```

## Quick Start

```bash
export MOTHERDUCK_TOKEN=<your_token>
cd dapes/gme_mart

# Create schemas on MotherDuck
python src/resource/run_ddl.py --target cloud

# Run full pipeline
dbt seed --profiles-dir . --target cloud
dbt run --profiles-dir . --target cloud
dbt test --profiles-dir . --target cloud
dbt docs generate --profiles-dir . --target cloud
```

## Design Methodology

Adapted from Shopee's Kimball data warehouse practices (10 repos, 9 presentations studied):

- **Bus Matrix** — dimensions x business processes (DE101)
- **DDL/DML separation** — explicit schemas before transforms (item_mart)
- **Window aggregations** — `_1d`, `_nd`, `_td` suffixes (order_mart)
- **Accumulating snapshot** — lifecycle tracking (Star-Schema slides)
- **Role-playing dimensions** — same dim as multiple FKs (E-Commerce slides)
- **Aggregate facts** — pre-computed for speed (E-Commerce Part 2)
- **Three-tier DQC** — pre/partial/post validation (cube-prepare)
- **OBT pattern** — wide denormalized consumption table (daas-batch)

Full pattern catalog: `dapes/gme_mart/docs/` (~2600 lines across 6 documents)

## Adding a New Mart

1. Create `dapes/<new_mart>/` (or `<project>/<new_mart>/`)
2. Copy structure from `gme_mart/` (src/ddl, src/dml, seeds, tests)
3. Add workflow in `.github/workflows/`
4. Share conformed dimensions via `shared/`

## License

Private repository. Part of the DragonRook MCP ecosystem.

# Shopee order_mart Patterns — Applicable to GME Mart

**Source:** `E:\Shopee\Shopee 2022\Git\order_mart`

## Table Registry (from Airflow DAG)

### DIM Tables (12)
- `order_mart_dim_bi_exclude_order` — exclusion rules
- `order_mart_dim_checkout_status` — status codes
- `order_mart_dim_exchange_rate` — FX rates (multi-region)
- `order_mart_dim_logistics_status` — shipping states
- `order_mart_dim_order_backend_status` — backend state machine
- `order_mart_dim_order_frontend_status` — customer-facing state
- `order_mart_dim_payment_method` — payment types
- `order_mart_dim_promotion_type` — promo classification
- `order_mart_dim_voucher` — voucher details

### DWD Tables (13)
- `_di` suffix = daily increment (append)
- `_df` suffix = daily full (snapshot/replace)
- Multiple grain levels: order-level, item-level, audit-log-level

### DWS Tables (16) — Window Patterns
| Suffix | Meaning | Example |
|---|---|---|
| `_1d` | 1-day snapshot | `dws_seller_gmv_1d` |
| `_nd` | N-day rolling window | `dws_buyer_gmv_nd` |
| `_td` | To-date (cumulative) | `dws_item_gmv_td` |
| `_mtd` | Month-to-date | `dws_sku_gmv_mtd` |

## Patterns to Adopt in gme_mart

### 1. Window Aggregations (Priority: HIGH)
Currently we only have `_1d` tables. Add:
- `gme_dws_strike_gex_nd` — trailing N-day GEX trend (detect regime shifts)
- `gme_dws_daily_snapshot_td` — cumulative since first pull (position P&L history)

### 2. Status Code Dimensions
order_mart has 7 status-code DIMs. We could add:
- `gme_dim_theta_regime` — LOW/MEDIUM/HIGH with configurable thresholds
- `gme_dim_moneyness` — OTM/NEAR/ATM/ITM with boundary rules

### 3. Multi-Region → Multi-Expiry
Shopee runs per-region (9 regions × all tables). Our equivalent:
- Per-expiry aggregations (each expiry = a "region")
- Front-month vs all-expiry toggle

### 4. Backfill Scripts
order_mart has `src/backfill/` with per-table backfill scripts.
We need: ability to backfill historical CBOE data (currently only pulling today's snapshot).

## Alert Pattern
Pan Min (operator's Shopee senior) is CC'd on all order_mart alerts.
DAG schedule: daily, SLA-monitored, Slack/email on failure.

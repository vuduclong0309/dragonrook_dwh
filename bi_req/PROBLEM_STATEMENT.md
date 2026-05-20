# Business Problem Statement — DragonRook DWH

## Why monitor GME options via a data warehouse?

GameStop (GME) has a uniquely complex derivatives landscape: two warrant series with different strikes and expiries, an options chain influenced by meme-stock dynamics, and gamma exposure (GEX) regimes that shift rapidly around earnings events. Tracking this manually — copying numbers from Barchart, swaggystocks, and CBOE into spreadsheets — is error-prone and doesn't scale across instruments or time horizons.

Prior to the DWH, market analysis relied on ad-hoc ChatGPT web searches (the "makeshift tools" era). These produced useful one-time snapshots but had no persistence, no version history, no automated refresh, and no way to validate whether the numbers were correct.

## What decisions does this data inform?

The DWH produces verified, source-tagged market data that supports:

- **Warrant monitoring.** Intrinsic value, moneyness, days-to-expiry, and theta regime for both warrant series — enabling timing decisions around accumulation or exit windows.
- **IV cycle tracking.** Implied volatility trends across the earnings cycle (low-IV base → pre-ER lift → post-ER crush), with historical baselines for comparison.
- **GEX regime detection.** Net gamma exposure by strike, regime classification (positive expanding, stable, negative), flip alerts, and trend analysis — informing whether the market is likely to dampen or amplify moves.
- **Flow pressure analysis.** Unusual volume-to-open-interest ratios and aggregate flow signals that flag potential directional bets by institutional or large retail participants.
- **Max pain and P/C analysis.** Per-expiry max pain levels and put/call ratios validated against external sources (swaggystocks, Barchart) — supporting strike selection and hedge calibration.

## Architecture context

DragonRook DWH is the **data infrastructure layer** — it produces verified numbers. Trading decisions, position sizing, and strategy execution are downstream consumer concerns, not in scope for the DWH.

The system uses Kimball methodology adapted from production data warehouse practices:
- Four-tier layer architecture: ODS (raw ingestion) → DIM (conformed dimensions) → DWD (atomic facts) → DWS (aggregated summaries) → ADS (one-big-table for consumption)
- DDL/DML separation for explicit schema governance
- Three-tier DQC (Data Quality Contract) with external reconciliation
- Every number carries a source tag and a verification path

## Data sources

| Source | Method | Frequency | Cost |
|--------|--------|-----------|------|
| CBOE delayed options chain | MotherDuck httpfs (`read_json_auto`) | Daily, weekdays | Free (15-min delay) |
| Yahoo Finance (XAUUSD via `GC=F`) | Python yfinance → MotherDuck | Daily, weekdays | Free |

## What the DWH is NOT

- A trading bot or signal generator.
- A real-time streaming system (daily EOD grain in v1).
- A multi-tenant platform (single-operator system).
- A replacement for broker-provided analytics — it complements them with historical depth and cross-instrument analysis.

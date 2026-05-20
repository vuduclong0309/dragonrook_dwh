# DaPES Context — Business Background

Adapted from the DaPES Wiki (Sections 1–3). Sanitized: no operator position sizes, no account balances.

---

## 1. Project Identity

**DaPES** ("Derivative Ape") is a guardian-AI-assisted GME options and equity analysis system.

| Version | Period | Platform | Status |
|---------|--------|----------|--------|
| V1 | Q1–Q2 2025 | IBKR | Archived — weekly options focus |
| V2 | May–Nov 2025 | IBKR (SG) | Archived — warrant accumulation era |
| V3 | Nov–Dec 2025 | IBKR (SG) | Dormant — warrant position held |
| **V3.1** | **May 2026 →** | **IBKR + dbt-duckdb + MotherDuck** | **Active — DWH scaffolding** |

**Lineage:** V1 (pre-warrant, weekly options) → V2 (added warrant dividend, shifted to weekly cadence) → V3 (warrant-centric barbell, pre-ER flatten rule) → V3.1 (Kimball DWH for automated market data pipelines).

The DragonRook DWH is the data infrastructure layer for V3.1, replacing the ad-hoc ChatGPT market scan workflows from the V2/V3 era with automated, testable, version-controlled data pipelines.

---

## 2. Warrant Map (Two Series)

GME has two distinct warrant series. Confusing them is a data quality error the DWH must prevent.

| Series | Ticker | Strike | Expiry | Origin |
|--------|--------|--------|--------|--------|
| Series A (original) | GME.WS | $19.94 | Jun 2026 | Pre-dividend, earlier instrument |
| Oct 2025 dividend warrants | GME1 / WAR | $32.00 | Oct 30, 2026 | 1-per-10-shares dividend, Oct 3 2025 record date |

**Key data considerations:**
- GME1 options chain is OCC-adjusted — wide spreads, poor liquidity. The DWH must flag GME1 vs GME chain data distinctly.
- Warrant monitoring models (`gme_dws_warrant_monitor_1d`, `gme_dws_warrant_mtm_1d`, `gme_dws_warrant_lifecycle_td`) track intrinsic value, moneyness, and DTE for these instruments.
- The DWH does NOT make trading recommendations about warrants — it provides the verified data needed for the operator to make those decisions.

---

## 3. Why This Data Matters

The DaPES system evolved through three versions of manual and semi-automated market analysis. Each version revealed the same bottleneck: **reliable, persistent, validated market data is the foundation** — without it, analysis is ad-hoc and unverifiable.

The DragonRook DWH addresses this by:
- Automating the daily market scan that was previously a manual ChatGPT workflow
- Providing historical depth (not just today's snapshot, but trend over time)
- Validating every metric against external sources (swaggystocks for max pain, Barchart for P/C ratios)
- Source-tagging all numbers so the operator knows provenance: `[REAL_API]` for live CBOE data, `[THEORETICAL]` for computed regime labels

This is the "boring infrastructure" that makes everything else — cycle timing, warrant monitoring, flow analysis — trustworthy.

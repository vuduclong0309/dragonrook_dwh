# Shopee Kimball Financial Services Patterns — Applicable to GME Mart

**Source:** `E:\Shopee\Shopee Slide Archive\Kimball Sharing - Financial Services.pptx`
**Authors:** Stephen Fang & James Chien (Shopee DE team)

## Key Patterns

### 1. Supertype / Subtype for Heterogeneous Products (DIRECTLY APPLICABLE)

Financial services offer disparate product lines (checking accounts vs certificates of deposit).

- **Supertype fact table** = global view across ALL products (limited common facts)
- **Subtype fact table** = in-depth view for ONE product type (special facts)

**Rules:**
- Do NOT include subtype facts in supertype table (too many inappropriate facts)
- Subtype tables MUST contain supertype facts + attributes (avoid cross-joins)

**GME Mart application:**
- Supertype: `gme_dwd_instrument_di` — common facts across warrants, options, shares (price, volume, date)
- Subtype: `gme_dwd_option_contract_di` — option-specific (greeks, strike, expiry, OI, IV)
- Subtype: `gme_dwd_warrant_di` — warrant-specific (intrinsic, moneyness, theta regime)

### 2. Hot Swappable Dimension

Multiple alternate versions of a dimension swapped at query time. Same fact table, different dimensional views.

**GME Mart application:**
- Same options chain fact, but swappable by:
  - Front-month view (nearest expiry only)
  - All-expiry view (every contract)
  - LEAP-only view (DTE > 365)

### 3. Degenerate Dimensions

Fields that don't warrant their own table: option_symbol, trade_id, contract identifier.

**Already implemented:** `option_symbol` in our DWD is a degenerate dimension (stored in fact, not joined).

### 4. Mini-Dimensions (for Rapidly Changing Attributes)

Split volatile attributes from stable dimension. Example: User Quota (changes daily) split from User (stable).

**GME Mart application:**
- Greeks (delta, gamma, theta, vega) change every tick — these are FACTS, not dimensions ✅ (we already model them correctly as fact columns)
- IV percentile rank is a derived volatile attribute — candidate for mini-dimension if we add historical context

### 5. Cash Loan Bus Matrix → Options Flow Mapping

Shopee Cash Loan process: apply → disburse → instalment → bill → repay

**Options flow equivalent:**
| Cash Loan | Options |
|---|---|
| Apply | Quote / List |
| Disburse | Trade execution |
| Instalment | Position holding (daily mark-to-market) |
| Bill | Assignment / Exercise |
| Repay | Settlement / Expiry |

## Kimball Lifecycle Pitfalls (from DW/BI Lifecycle Overview.pptx)

Most relevant for gme_mart:

- **Pitfall 4:** Don't build dimensional models without conformed dimensions (our `dim_date` IS conformed across future xauusd_mart ✅)
- **Pitfall 7:** Don't over-normalize at the expense of presentation layer (our DWS views are pre-aggregated for the briefing skill ✅)
- **Pitfall 3:** Don't load only summarized data — keep atomic grain (our ODS has every contract row ✅)
- **Pitfall 8:** Don't tackle multi-year project — iterate (we did: Phase 0 → Phase 1 → DQC ✅)

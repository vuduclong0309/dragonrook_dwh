# GEX Verification SOP

Manual spot-check procedure for operator validation of `gme_dws_strike_gex_1d` net GEX.

## When to run

- After any change to the `gex_contribution` macro or DWD filters
- If HEARTBEAT DQC scorecard shows GEX row as ⚠️
- Quarterly maintenance validation

## Prerequisites

- `MOTHERDUCK_TOKEN` set in environment
- Python 3.10+ with `duckdb` package installed
- Access to the `gme_db` MotherDuck database

## Step 1: Run automated reference check

```bash
MOTHERDUCK_TOKEN=<token> python scripts/dapes/gex_reference.py
```

Expected: all dates PASS with < 0.1% relative divergence between Python recompute and dbt mart.

## Step 2: Run dbt singular test

```bash
cd dapes/gme_mart
dbt test --select test_gex_reasonableness --target cloud
```

Expected: test passes (no rows returned = no 3σ outliers detected).

## Step 3: Manual sanity check (10 minutes)

Pick the top-GEX strike for the latest date and verify by hand:

```sql
-- Run in MotherDuck console or DuckDB CLI
-- 1. Get the top strike from the mart
SELECT pull_date, strike, expiry, call_gex, put_gex, net_gex
FROM gme_db.dws.gme_dws_strike_gex_1d
WHERE pull_date = (SELECT MAX(pull_date) FROM gme_db.dws.gme_dws_strike_gex_1d)
ORDER BY ABS(net_gex) DESC
LIMIT 5;

-- 2. For the top strike, pull raw contracts and verify
SELECT
    option_type, gamma, open_interest, underlying_close AS spot,
    COALESCE(gamma,0) * COALESCE(open_interest,0) * 100
        * POWER(underlying_close, 2) * 0.01
        * CASE WHEN option_type = 'call' THEN 1 ELSE -1 END
        AS manual_gex
FROM gme_db.ods.gme_ods_cboe_options_chain
WHERE pull_date = (SELECT MAX(pull_date) FROM gme_db.dws.gme_dws_strike_gex_1d)
  AND strike = <TOP_STRIKE>
  AND expiry IS NOT NULL
  AND open_interest > 0
  AND (expiry - pull_date) > 7
ORDER BY ABS(manual_gex) DESC;

-- 3. Sum manual_gex — should match mart net_gex for that strike within rounding
```

## Step 4: Document results

Record in the PR or HEARTBEAT:
- Date(s) validated
- Python reference result (PASS/FAIL + relative diff %)
- dbt test result (pass/fail)
- Manual spot-check strike + result
- Source tag: [PYTHON_SIM] for reference, [REAL_API] for mart values

## Failure investigation

If divergence > 0.1%:
1. Check filter alignment: DWD applies `OI > 0`, `DTE > 7`, `expiry IS NOT NULL`, `underlying_close IS NOT NULL`
2. Check for NULL gamma propagation (COALESCE should handle, but verify)
3. Check if OCC symbol parsing dropped valid 18-char symbols
4. Check for duplicate rows in ODS (run `test_ods_no_duplicates`)

If 3σ test fails:
1. This is NOT necessarily a bug — could be genuine market event (earnings, squeeze)
2. Check if the date is a known high-vol event (Fed, earnings, OPEX)
3. If justified, document as known-good and move on
4. If no justification, investigate data freshness (stale pull?) or formula regression

## Scorecard update

After successful validation:
- GEX row moves from ⚠️ to ⚠️★ (Option B verified, no external ground truth)
- Footnote: "Verified via Python reference recompute + 3σ reasonableness test. No free-tier external source available for absolute validation."
- Update HEARTBEAT with validation date and method

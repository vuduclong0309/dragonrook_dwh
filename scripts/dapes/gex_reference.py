"""
GEX reference implementation — recompute from raw ODS and compare vs DWS mart.
[PYTHON_SIM] Independent validation of gme_dws_strike_gex_1d.

Usage:
    MOTHERDUCK_TOKEN=<token> python scripts/dapes/gex_reference.py [--dates 2026-05-06,2026-05-07,2026-05-08]

Compares Python-computed net GEX per (trade_date, strike) against the dbt mart output.
Exits non-zero if any date shows > 0.1% relative divergence on total net GEX.
"""
import argparse
import os
import sys

import duckdb


def connect():
    token = os.environ.get("MOTHERDUCK_TOKEN", "")
    if not token:
        print("[ERROR] MOTHERDUCK_TOKEN not set", file=sys.stderr)
        sys.exit(1)
    return duckdb.connect(f"md:gme_db?motherduck_token={token}")


def get_available_dates(con, n=3):
    """Return the most recent N pull_dates from the ODS table."""
    df = con.execute(
        f"SELECT DISTINCT pull_date FROM gme_ods_cboe_options_chain "
        f"ORDER BY pull_date DESC LIMIT {n}"
    ).fetchdf()
    return sorted(df["pull_date"].tolist())


def recompute_gex_from_ods(con, trade_date):
    """
    Recompute GEX from raw ODS applying the same filters and formula as dbt.
    Formula: gamma * OI * 100 * spot^2 * 0.01 * sign
    Filters: expiry IS NOT NULL, OI > 0, strike IS NOT NULL,
             underlying_close IS NOT NULL, DTE > 7
    """
    query = """
    SELECT
        pull_date,
        strike,
        expiry,
        option_type,
        gamma,
        open_interest,
        underlying_close AS spot,
        COALESCE(gamma, 0)
            * COALESCE(open_interest, 0)
            * 100
            * POWER(underlying_close, 2)
            * 0.01
            * CASE WHEN option_type = 'call' THEN 1 ELSE -1 END
            AS gex_contribution_py
    FROM gme_ods_cboe_options_chain
    WHERE pull_date = ?
      AND expiry IS NOT NULL
      AND open_interest > 0
      AND strike IS NOT NULL
      AND underlying_close IS NOT NULL
      AND (expiry - pull_date) > 7
    """
    return con.execute(query, [trade_date]).fetchdf()


def get_dws_gex(con, trade_date):
    """Get the mart-produced GEX by strike for a given date."""
    query = """
    SELECT
        pull_date,
        strike,
        expiry,
        call_gex,
        put_gex,
        net_gex
    FROM gme_dws_strike_gex_1d
    WHERE pull_date = ?
    """
    return con.execute(query, [trade_date]).fetchdf()


def compare_date(con, trade_date):
    """Compare Python recompute vs dbt mart for one date. Returns (pass, details)."""
    ods_df = recompute_gex_from_ods(con, trade_date)
    dws_df = get_dws_gex(con, trade_date)

    if ods_df.empty:
        return None, f"  [SKIP] No ODS data for {trade_date}"

    if dws_df.empty:
        return False, f"  [FAIL] No DWS data for {trade_date} but ODS has {len(ods_df)} rows"

    py_total = ods_df["gex_contribution_py"].sum()
    dws_total = dws_df["net_gex"].sum()

    if abs(dws_total) < 1e-10 and abs(py_total) < 1e-10:
        rel_diff = 0.0
    elif abs(dws_total) < 1e-10:
        rel_diff = float("inf")
    else:
        rel_diff = abs(py_total - dws_total) / abs(dws_total)

    passed = rel_diff <= 0.001  # 0.1% tolerance

    details = (
        f"  Date: {trade_date}\n"
        f"  Python net GEX:  {py_total:>15,.2f} [PYTHON_SIM]\n"
        f"  DWS mart net GEX:{dws_total:>15,.2f} [REAL_API]\n"
        f"  Relative diff:   {rel_diff*100:.4f}%\n"
        f"  ODS rows used:   {len(ods_df)}\n"
        f"  DWS strikes:     {len(dws_df)}\n"
        f"  Result:          {'PASS' if passed else 'FAIL'}"
    )
    return passed, details


def main():
    parser = argparse.ArgumentParser(description="GEX reference validation")
    parser.add_argument(
        "--dates",
        type=str,
        default="",
        help="Comma-separated trade dates (YYYY-MM-DD). Default: latest 3.",
    )
    args = parser.parse_args()

    con = connect()

    if args.dates:
        dates = [d.strip() for d in args.dates.split(",") if d.strip()]
    else:
        dates = get_available_dates(con, n=3)

    if not dates:
        print("[ERROR] No trade dates found in ODS", file=sys.stderr)
        sys.exit(1)

    print("=" * 60)
    print("GEX REFERENCE VALIDATION")
    print("Formula: gamma * OI * 100 * spot^2 * 0.01 * sign")
    print(f"Dates to compare: {len(dates)}")
    print("=" * 60)

    results = []
    for trade_date in dates:
        passed, details = compare_date(con, trade_date)
        print(f"\n{details}")
        if passed is not None:
            results.append(passed)

    con.close()

    print("\n" + "=" * 60)
    total = len(results)
    passes = sum(results)
    fails = total - passes
    print(f"SUMMARY: {passes}/{total} dates passed, {fails} failed")
    print("=" * 60)

    if fails > 0:
        print("\n[FAIL] GEX divergence detected — investigate formula or filter mismatch")
        sys.exit(1)
    elif total == 0:
        print("\n[WARN] No dates could be compared")
        sys.exit(2)
    else:
        print("\n[PASS] Python reference matches dbt mart within 0.1% tolerance")
        sys.exit(0)


if __name__ == "__main__":
    main()

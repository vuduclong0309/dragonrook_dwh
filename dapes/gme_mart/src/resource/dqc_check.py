"""DQC fact check — query gme_db and print key metrics for validation."""
import duckdb, os

token = os.environ.get("MOTHERDUCK_TOKEN", "")
if not token:
    raise SystemExit("[ERROR] MOTHERDUCK_TOKEN not set")

con = duckdb.connect(f"md:gme_db?motherduck_token={token}")

snap = con.execute("SELECT * FROM gme_dws_daily_snapshot_1d").fetchdf()
print("=== DAILY SNAPSHOT ===")
print(snap.to_string(index=False))

w = con.execute(
    "SELECT spot, warrant_strike, intrinsic_total, moneyness_pct, "
    "distance_to_strike_pct, moneyness, theta_regime, dte "
    "FROM gme_dws_warrant_monitor_1d"
).fetchdf()
print("\n=== WARRANT MONITOR ===")
print(w.to_string(index=False))

oi = con.execute(
    "SELECT "
    "SUM(CASE WHEN option_type='put' THEN open_interest ELSE 0 END) as put_oi, "
    "SUM(CASE WHEN option_type='call' THEN open_interest ELSE 0 END) as call_oi "
    "FROM gme_dwd_option_contract_di"
).fetchdf()
print("\n=== OI TOTALS (excl weeklies) ===")
print(oi.to_string(index=False))

# Check how many rows have null expiry in ODS
nulls = con.execute(
    "SELECT COUNT(*) as total, "
    "SUM(CASE WHEN expiry IS NULL THEN 1 ELSE 0 END) as null_expiry "
    "FROM gme_ods_cboe_options_chain"
).fetchdf()
print("\n=== ODS NULL CHECK ===")
print(nulls.to_string(index=False))

con.close()
print("\n[DONE]")

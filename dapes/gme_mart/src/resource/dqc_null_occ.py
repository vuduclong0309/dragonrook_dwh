"""Investigate null-expiry OCC symbols in ODS."""
import duckdb, os

token = os.environ.get("MOTHERDUCK_TOKEN", "")
if not token:
    raise SystemExit("[ERROR] MOTHERDUCK_TOKEN not set")

con = duckdb.connect(f"md:gme_db?motherduck_token={token}")

# What do the non-standard symbols look like?
nulls = con.execute(
    "SELECT option_symbol, LENGTH(option_symbol) as len, bid, ask, open_interest, gamma "
    "FROM gme_ods_cboe_options_chain "
    "WHERE expiry IS NULL "
    "ORDER BY open_interest DESC NULLS LAST "
    "LIMIT 20"
).fetchdf()
print("=== TOP 20 NULL-EXPIRY SYMBOLS (by OI) ===")
print(nulls.to_string(index=False))

# Distribution of symbol lengths
lens = con.execute(
    "SELECT LENGTH(option_symbol) as len, COUNT(*) as cnt, "
    "SUM(CASE WHEN expiry IS NULL THEN 1 ELSE 0 END) as null_cnt "
    "FROM gme_ods_cboe_options_chain "
    "GROUP BY LENGTH(option_symbol) ORDER BY cnt DESC"
).fetchdf()
print("\n=== SYMBOL LENGTH DISTRIBUTION ===")
print(lens.to_string(index=False))

# Top OI strikes validation (from our DWD)
top_oi = con.execute(
    "SELECT strike, SUM(open_interest) as total_oi, "
    "SUM(CASE WHEN option_type='call' THEN open_interest ELSE 0 END) as call_oi, "
    "SUM(CASE WHEN option_type='put' THEN open_interest ELSE 0 END) as put_oi "
    "FROM gme_dwd_option_contract_di "
    "WHERE pull_date = (SELECT MAX(pull_date) FROM gme_dwd_option_contract_di) "
    "GROUP BY strike ORDER BY total_oi DESC LIMIT 10"
).fetchdf()
print("\n=== TOP 10 OI STRIKES (latest pull) ===")
print(top_oi.to_string(index=False))

con.close()

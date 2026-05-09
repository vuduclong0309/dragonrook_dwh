import duckdb, os
token = os.environ["MOTHERDUCK_TOKEN"]
con = duckdb.connect(f"md:gme_db?motherduck_token={token}")
print(con.execute("SELECT DISTINCT series_type, COUNT(*) as cnt FROM gme_dwd_option_contract_di GROUP BY series_type ORDER BY cnt DESC").fetchdf().to_string(index=False))
con.close()

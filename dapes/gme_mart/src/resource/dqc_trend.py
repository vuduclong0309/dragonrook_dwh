"""Verify gme_dws_gex_trend_nd data."""
import duckdb, os

token = os.environ.get("MOTHERDUCK_TOKEN", "")
if not token:
    raise SystemExit("[ERROR] MOTHERDUCK_TOKEN not set")

con = duckdb.connect(f"md:gme_db?motherduck_token={token}")

trend = con.execute("SELECT * FROM gme_dws_gex_trend_nd ORDER BY pull_date").fetchdf()
print("=== GEX TREND (N-day rolling) ===")
print(trend.to_string(index=False))

# Summary
print(f"\nRows: {len(trend)}")
if len(trend) > 0:
    latest = trend.iloc[-1]
    print(f"Latest: {latest['pull_date']} | GEX regime: {latest['gex_regime']}")
    print(f"  Net GEX: {latest['net_gex']:,.0f} | 5d avg: {latest['net_gex_avg_5d']:,.0f}")
    print(f"  Spot: {latest['spot']:.2f} | 5d avg: {latest['spot_avg_5d']:.2f}")
    print(f"  Max pain distance: {latest['max_pain_distance_pct']:.1f}%")

con.close()

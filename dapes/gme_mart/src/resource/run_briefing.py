"""Run the full GME Mart briefing from MotherDuck OBT dashboard.
Validates the entire pipeline end-to-end: CBOE → ODS → DWD → DWS → ADS → briefing.

Usage: MOTHERDUCK_TOKEN=... python run_briefing.py
"""
import duckdb
import os
import sys
from datetime import date

token = os.environ.get("MOTHERDUCK_TOKEN", "")
if not token:
    raise SystemExit("[ERROR] MOTHERDUCK_TOKEN not set")

con = duckdb.connect(f"md:gme_db?motherduck_token={token}", read_only=True)

# OBT Dashboard — single query
dash = con.execute("""
    SELECT * FROM gme_ads_warrant_dashboard
    WHERE pull_date = (SELECT MAX(pull_date) FROM gme_ads_warrant_dashboard)
""").fetchdf()

if dash.empty:
    print("[ERROR] No data in dashboard")
    sys.exit(1)

r = dash.iloc[0]

# Top 5 GEX
gex = con.execute("""
    SELECT strike, expiry, net_gex, total_oi, gex_rank
    FROM gme_dws_strike_gex_1d
    WHERE pull_date = (SELECT MAX(pull_date) FROM gme_dws_strike_gex_1d)
      AND gex_rank <= 5
    ORDER BY gex_rank
""").fetchdf()

# Flow alerts
flow = con.execute("""
    SELECT strike, expiry, option_type, volume, oi_delta_1d, flow_pressure_label
    FROM gme_dws_flow_pressure_1d
    WHERE pull_date = (SELECT MAX(pull_date) FROM gme_dws_flow_pressure_1d)
      AND flow_pressure_label IN ('UNUSUAL_FLOW', 'POSITION_BUILD')
    ORDER BY ABS(oi_delta_1d) DESC
    LIMIT 5
""").fetchdf()

# Events next 14 days
events = con.execute("""
    SELECT event_date, event_type, event_name, impact
    FROM macro_events_2025_2027
    WHERE event_date BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL 14 DAY
    ORDER BY event_date
""").fetchdf()

con.close()

# Format briefing
print(f"## DaPES Daily Briefing — {r['pull_date']}")
print()
print(f"### Position Summary [REAL_API]")
print(f"| Metric | Value |")
print(f"|---|---|")
print(f"| Spot | ${r['spot']:.2f} |")
print(f"| Max Pain | ${r['max_pain_strike']:.2f} (convergence: {r['max_pain_convergence_pct']:.1f}%) |")
print(f"| Net GEX | ${r['net_gex']:,.0f} |")
print(f"| P/C Ratio | {r['pc_ratio']:.3f} |")
print()
print(f"### GEX Regime [REAL_API + PYTHON_SIM]")
gex_regime = r.get('gex_regime', 'N/A')
gex_alert = r.get('gex_alert', 'NO_ALERT')
print(f"- Regime: **{gex_regime}**")
print(f"- Net GEX 5d avg: ${r.get('net_gex_avg_5d', 0):,.0f}")
print(f"- GEX delta 1d: ${r.get('net_gex_delta_1d', 0):,.0f}")
print(f"- Alert: {gex_alert}")
print()
print(f"### Warrant Monitor [REAL_API]")
print(f"- Strike: ${r.get('warrant_strike', 0):.2f} | DTE: {r.get('warrant_dte', 'N/A')} days")
print(f"- Moneyness: {r.get('moneyness', 'N/A')} ({r.get('distance_to_strike_pct', 0):.1f}% from strike)")
print(f"- Theta regime: {r.get('theta_regime', 'N/A')}")
print(f"- Intrinsic: ${r.get('intrinsic_total', 0):.2f}")
print(f"- Share value: ${r.get('share_position_value', 0):,.2f}")
print(f"- Total position: ${r.get('total_position_value', 0):,.2f}")
print()
warrant_mark = r.get('warrant_mark')
if warrant_mark and warrant_mark > 0:
    print(f"### Warrant MTM [REAL_API]")
    print(f"- Market value: ${r.get('warrant_market_value', 0):,.2f}")
    print(f"- Daily P&L: ${r.get('daily_unrealized_pnl', 0):,.2f}")
    print(f"- IV: {r.get('warrant_iv', 0):.1%}")
    print(f"- Position Greeks: delta={r.get('position_delta', 0):.1f} theta={r.get('position_theta', 0):.2f} vega={r.get('position_vega', 0):.1f}")
    print()
iv_regime = r.get('iv_regime', 'N/A')
print(f"### IV Regime [REAL_API]")
print(f"- ATM IV: {r.get('iv_atm', 0):.1%}")
print(f"- Percentile: {r.get('iv_percentile_252d', 0):.0f}%")
print(f"- Regime: {iv_regime} ({r.get('iv_history_days', 0):.0f} days history)")
print()
print(f"### Top GEX Strikes [REAL_API + PYTHON_SIM]")
print(gex.to_string(index=False))
print()
flow_signal = r.get('flow_signal', 'NORMAL')
print(f"### Flow Signals [{flow_signal}]")
if not flow.empty:
    print(flow.to_string(index=False))
else:
    print("No unusual flow detected.")
print()
if not events.empty:
    print(f"### Upcoming Events (14d) [THEORETICAL]")
    print(events.to_string(index=False))
print()
print(f"### Fox Assessment")
print(f"GME at ${r['spot']:.2f}, {r.get('distance_to_strike_pct', 0):.0f}% from $32 warrant strike.")
print(f"GEX regime {gex_regime} — {'dealers stabilizing (long gamma)' if 'POSITIVE' in str(gex_regime) else 'dealers amplifying (short gamma)' if 'NEGATIVE' in str(gex_regime) else 'neutral positioning'}.")
print(f"Warrant DTE {r.get('warrant_dte', '?')} days, theta {r.get('theta_regime', '?')}.")
print(f"Max pain ${r['max_pain_strike']:.0f} ({'converging' if r['max_pain_convergence_pct'] < 3 else 'diverging'} from spot).")

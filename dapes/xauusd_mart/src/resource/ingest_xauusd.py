"""Ingest XAUUSD daily bars from Yahoo Finance into MotherDuck/DuckDB.

Provider choice: yfinance (GC=F for COMEX gold futures)
Rationale [THEORETICAL]:
  - Free, no API key required, no rate-limit issues for daily-bar pulls
  - GC=F (COMEX gold front-month continuous) is the canonical gold futures benchmark
  - Alternatives considered:
    * OpenBB: more structured but heavier dependency, requires Platform install
    * IBKR: gated on DaPES-IBKR-0.5 design ticket (out of scope)
  - Limitation: yfinance volume data for GC=F may reflect front-month only;
    for v1 daily bars this is acceptable

Usage:
  python ingest_xauusd.py [--target cloud|dev] [--days 5]
"""
import argparse
import os
import sys
from datetime import datetime, timedelta

import duckdb
import yfinance as yf


TICKER = "GC=F"


def get_connection(target: str):
    if target == "cloud":
        token = os.environ.get("MOTHERDUCK_TOKEN")
        if not token:
            print("[ERROR] MOTHERDUCK_TOKEN env var required for --target cloud")
            sys.exit(1)
        return duckdb.connect(f"md:xauusd_db?motherduck_token={token}")
    else:
        return duckdb.connect("xauusd_mart_dev.duckdb")


def fetch_bars(days: int) -> "pd.DataFrame":
    end = datetime.utcnow().date()
    start = end - timedelta(days=days)
    ticker = yf.Ticker(TICKER)
    df = ticker.history(start=str(start), end=str(end), interval="1d")
    if df.empty:
        print(f"[WARN] No data returned for {TICKER} ({start} to {end})")
        return df
    df = df.reset_index()
    df = df.rename(columns={
        "Date": "trade_date",
        "Open": "open",
        "High": "high",
        "Low": "low",
        "Close": "close",
        "Volume": "volume",
    })
    df["trade_date"] = df["trade_date"].dt.date
    df["ticker"] = "XAUUSD"
    df["provider"] = "yfinance"
    df["source_symbol"] = TICKER
    df["pull_ts_utc"] = datetime.utcnow()
    return df[["trade_date", "ticker", "provider", "source_symbol",
               "open", "high", "low", "close", "volume", "pull_ts_utc"]]


def upsert(con, df):
    """Insert new rows, skip duplicates on trade_date."""
    con.execute("""
        CREATE TABLE IF NOT EXISTS xauusd_ods_daily_bar (
            trade_date    DATE NOT NULL,
            ticker        VARCHAR NOT NULL,
            provider      VARCHAR NOT NULL,
            source_symbol VARCHAR,
            open          DOUBLE,
            high          DOUBLE,
            low           DOUBLE,
            close         DOUBLE,
            volume        BIGINT,
            pull_ts_utc   TIMESTAMP,
            PRIMARY KEY (trade_date)
        )
    """)
    existing = con.execute(
        "SELECT trade_date FROM xauusd_ods_daily_bar"
    ).fetchdf()
    existing_dates = set(existing["trade_date"].tolist()) if not existing.empty else set()

    new_rows = df[~df["trade_date"].isin(existing_dates)]
    if new_rows.empty:
        print("[INGEST] No new rows to insert")
        return 0

    con.execute("INSERT INTO xauusd_ods_daily_bar SELECT * FROM new_rows")
    print(f"[INGEST] Inserted {len(new_rows)} new rows")
    return len(new_rows)


def main():
    parser = argparse.ArgumentParser(description="Ingest XAUUSD daily bars")
    parser.add_argument("--target", choices=["dev", "cloud"], default="cloud")
    parser.add_argument("--days", type=int, default=5,
                        help="Number of calendar days to look back")
    args = parser.parse_args()

    df = fetch_bars(args.days)
    if df.empty:
        print("[INGEST] No data fetched, exiting")
        sys.exit(0)

    con = get_connection(args.target)
    upsert(con, df)

    total = con.execute("SELECT COUNT(*) FROM xauusd_ods_daily_bar").fetchone()[0]
    print(f"[INGEST] Total rows in xauusd_ods_daily_bar: {total}")
    con.close()


if __name__ == "__main__":
    main()

"""Run all DDL scripts against MotherDuck to create/verify table schemas.
Like Shopee item_mart_init.py — runs BEFORE dbt to ensure target schemas exist.

Usage:
  python run_ddl.py [--target cloud|dev]
"""
import argparse
import os
import sys
from pathlib import Path

import duckdb


def get_connection(target: str):
    if target == "cloud":
        token = os.environ.get("MOTHERDUCK_TOKEN")
        if not token:
            print("[ERROR] MOTHERDUCK_TOKEN env var required for --target cloud")
            sys.exit(1)
        # Create DB if not exists
        con = duckdb.connect(f"md:?motherduck_token={token}")
        con.execute("CREATE DATABASE IF NOT EXISTS gme_db")
        con.close()
        return duckdb.connect(f"md:gme_db?motherduck_token={token}")
    else:
        return duckdb.connect("gme_mart_dev.duckdb")


def run_ddl(con, ddl_dir: Path):
    """Execute all .sql files in ddl_dir recursively."""
    ddl_files = sorted(ddl_dir.rglob("*.sql"))
    print(f"[DDL] Found {len(ddl_files)} DDL files in {ddl_dir}")
    for f in ddl_files:
        rel = f.relative_to(ddl_dir)
        sql = f.read_text(encoding="utf-8")
        try:
            con.execute(sql)
            print(f"  [OK] {rel}")
        except Exception as e:
            print(f"  [ERROR] {rel}: {e}")


def main():
    parser = argparse.ArgumentParser(description="Run DDL for GME Mart")
    parser.add_argument("--target", choices=["dev", "cloud"], default="cloud")
    args = parser.parse_args()

    ddl_dir = Path(__file__).parent.parent / "ddl"
    con = get_connection(args.target)
    run_ddl(con, ddl_dir)

    # Verify
    tables = con.execute("SHOW TABLES").fetchall()
    print(f"\n[VERIFY] Tables in DB: {[t[0] for t in tables]}")
    con.close()


if __name__ == "__main__":
    main()

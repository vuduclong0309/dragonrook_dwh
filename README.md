# DragonRook DWH

Kimball-style data warehouse on MotherDuck. Each mart is a self-contained dbt project.

## Structure

```
dragonrook_dwh/
├── dapes/                     # DaPES project scope
│   └── gme_mart/              # GME options analytics
│       ├── src/ddl/           # Schema definitions (CREATE TABLE)
│       ├── src/dml/           # dbt models (transforms)
│       ├── src/resource/      # Utilities (DDL runner, etc.)
│       ├── seeds/             # Static data (holidays, macro events)
│       ├── dbt_project.yml
│       └── profiles.yml
├── shared/                    # Conformed dimensions (future)
└── .github/workflows/         # GitHub Actions scheduling
```

## Quick Start

```bash
# Set MotherDuck token
export MOTHERDUCK_TOKEN=<your_token>

# Run DDL (create schemas)
cd dapes/gme_mart
python src/resource/run_ddl.py --target cloud

# Run pipeline
dbt seed --profiles-dir . --target cloud
dbt run --profiles-dir . --target cloud
dbt test --profiles-dir . --target cloud
```

## Daily Schedule

GitHub Actions cron: `45 20 * * 1-5` (16:45 ET, weekdays)

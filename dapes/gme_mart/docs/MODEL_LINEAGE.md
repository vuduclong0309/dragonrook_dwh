# GME Mart — Model Lineage

Data flows top-to-bottom. Each arrow = a `{{ ref() }}` dependency.

```
                    CBOE httpfs (cdn.cboe.com)
                           │
                           ▼
                 ┌─────────────────────┐
                 │ gme_ods_cboe_       │
                 │ options_chain       │  ODS (incremental)
                 └─────────┬───────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
    ┌──────────────┐ ┌──────────┐ ┌──────────────┐
    │ gme_dwd_     │ │ gme_dim_ │ │ holidays/    │
    │ option_      │ │ date     │ │ macro_events │
    │ contract_di  │ │          │ │ (seeds)      │
    └──────┬───────┘ └──────────┘ └──────────────┘
           │
     ┌─────┼─────┬──────────┬──────────┬──────────┐
     ▼     ▼     ▼          ▼          ▼          ▼
  ┌──────┐┌────┐┌────────┐┌────────┐┌────────┐┌────────┐
  │strike││war-││gex_    ││warrant_││flow_   ││iv_     │
  │_gex  ││rant││trend   ││mtm     ││pressure││percen- │
  │_1d   ││_mon││_nd     ││_1d     ││_1d     ││tile_1d │
  └──┬───┘│itor│└───┬────┘└────────┘└───┬────┘└────────┘
     │    │_1d │    │                    │
     │    └──┬─┘    │                    │
     │       │      ▼                    ▼
     │       │  ┌────────┐         ┌──────────┐
     │       │  │gex_flip│         │unusual_  │
     │       │  │_alert  │         │flow_     │
     │       │  │_1d     │         │summary_1d│
     │       │  └───┬────┘         └────┬─────┘
     │       │      │                   │
     ▼       ▼      ▼                   ▼
  ┌──────────────────────────────────────────┐
  │        gme_dws_daily_snapshot_1d         │
  └────────────────────┬─────────────────────┘
                       │
     ┌─────────────────┼─────────────────────┐
     ▼                 ▼                     ▼
┌──────────┐  ┌──────────────────┐  ┌──────────────┐
│warrant_  │  │gme_ads_warrant_  │  │              │
│lifecycle │  │dashboard (OBT)   │  │ run_briefing │
│_td       │  │(40+ columns)     │  │ .py          │
└──────────┘  └──────────────────┘  └──────────────┘
```

## Layer Counts

| Layer | Models | Tests |
|---|---|---|
| DIM | 1 | 2 (unique, not_null) |
| ODS | 1 | 3 (not_null ×2, row_count) |
| DWD | 1 | 8 (not_null ×5, accepted_values ×2, null_greeks) |
| DWS | 10 | 15+ (not_null, accepted_values on enums) |
| ADS | 1 | 2 (not_null) |
| Seeds | 2 | — |
| Macro | 1 | — (gex_contribution) |
| **Total** | **15+2** | **30+** |

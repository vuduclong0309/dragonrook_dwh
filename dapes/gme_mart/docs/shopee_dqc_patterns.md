# Shopee DQC Patterns — Adapted for GME Mart

**Source:** `E:\Shopee\Shopee 2022\Git\validation_framework` + `order_mart/src/dml/dqc/`

## Shopee Test Framework

- `TestBase` abstract class: `get_test_name()`, `get_test_purpose()`, `get_test_result()` → (exit_code, result)
- Modular: one test module per mart (item_profile, user_segment, etc.)
- Each module has `test_inputs.py` (config) + `test_list.py` (registry)
- Runs via PySpark, emails report on failure

## 5 Standard Check Types (test_utils.py)

1. **Duplication** — GROUP BY PK, HAVING cnt > 1
2. **Row Count** — direct count comparison between runs
3. **Schema** — column name, datatype, nullable validation
4. **Data Diff** — set subtraction (rows in A not in B)
5. **Sampling Diff** — efficient large-table diffs via sampling

## order_mart DQC Pattern

- One DQC script per table (e.g., `dqc_order_mart_dwd_order_all_ent_di.py`)
- Results written to centralized `dqc_order_mart_count_di` table
- FULL OUTER JOIN old vs new results to detect delta/trend anomalies
- Metrics: row_cnt, item_cnt, duplicate_cnt, order_fraction

## Adapted for gme_mart (dbt tests/)

| Shopee Pattern | gme_mart Test | File |
|---|---|---|
| `duplication_test()` | `test_ods_no_duplicates.sql` | PK uniqueness on ODS |
| `duplication_test()` | `test_dwd_no_duplicates.sql` | PK uniqueness on DWD |
| `row_count_test()` | `test_ods_row_count.sql` | 500-3000 rows per pull |
| `dqc_data_loss` | `test_dwd_no_null_greeks.sql` | <5% null rate on Greeks |
| logic validation | `test_spot_range.sql` | Spot $5-$500 sanity |

## Future Enhancements (from Shopee)
- Centralized DQC results table (like `dqc_order_mart_count_di`)
- FULL OUTER JOIN trend detection (day-over-day anomaly)
- Schema drift detection
- Email/Slack alerting on DQC failure

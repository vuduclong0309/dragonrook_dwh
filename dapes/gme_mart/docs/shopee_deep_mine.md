# Shopee Data Engineering Deep Mine
## Patterns for GME Options Kimball DW (DuckDB/MotherDuck)

*Extracted 2026-05-09 from 5 Shopee repos + 2 Confluence slide decks*
*Source: E:\Shopee\Shopee 2022\Git\*

---

## 1. shopee-cube-prepare (Order Mart)

**What it is:** The core OLAP cube preparation pipeline for Shopee's order management domain.
Produces `order_mart__order_profile` and `order_mart__order_item_profile` tables that serve
as the star-schema fact tables for all downstream KPI marts.

### 1.1 Architecture: Three-DAG Pipeline

The order mart uses a **three-phase DAG chain**, each Airflow DAG triggers sequentially:

1. **`order_mart__dim_map_for_region_split`** -- builds dimension tables first
   - `dim_sellertype` (seller classification dimension)
   - `map_first_purchase` (first-purchase date mapping)
   - `dim_voucher_type`, `dim_category` (from BIDB)
   - `dim_exrate` (exchange rate dimension -- critical for multi-currency)

2. **`order_mart__order_item_profile_partial`** -- builds intermediate/partial fact tables
   - `order_mart__order_profile_partial`
   - `order_mart__order_item_profile_partial`
   - Runs validation between phases

3. **`order_mart__order_item_profile_tbl`** -- builds final production fact tables
   - `order_mart__order_profile` (order-grain fact)
   - `order_mart__order_item_profile` (order-item-grain fact)
   - Post-validation

**GME Applicability:** Our options mart should follow the same three-phase pattern:
1. Dimensions first (dim_ticker, dim_option_contract, dim_exchange, dim_date)
2. Intermediate staging tables (raw options + enrichment joins)
3. Final production fact tables (fact_option_trade, fact_option_eod)

### 1.2 Config Pattern: Environment-Aware BaseConfig

```python
# Pattern: BaseConfig with environment overrides via inheritance
class BaseConfig(object):
    SCHEMA_NAME = 'shopee'
    ORDER_PROFILE_DIR = SHOPEE_DIR + '/order_mart/order_profile/'
    ORDER_PROFILE_HIVE_TABLE_NAME = 'order_mart__order_profile'
    SCHEMA_INFO = {
        'shopee_schema': 'shopee',
        'tesla_schema': 'tesla'
    }
    REPAIR_COUNTRY_TABLE = True

class DevelopmentConfig(BaseConfig):
    def __init__(self):
        # Override paths with user-specific prefix
        self.ORDER_PROFILE_DIR = HDFS_PATH_DEVELOPMENT_PREFIX + self.ORDER_PROFILE_DIR
        self.ORDER_PROFILE_HIVE_TABLE_NAME = self.ORDER_PROFILE_HIVE_TABLE_NAME + '__debug'
        self.REPAIR_COUNTRY_TABLE = False

class TestingPipelineConfig(BaseConfig):
    def __init__(self):
        self.SCHEMA_NAME = 'test_shopee'
        self.SCHEMA_INFO = {
            'shopee_schema': 'test_shopee',
            'tesla_schema': 'test_shopee'
        }

def get_configuration(mode):
    if mode == "production": return ProductionConfig()
    if mode == "development": return DevelopmentConfig()
    if mode == "testing-pipeline": return TestingPipelineConfig()
```

**GME Applicability:** Directly translatable to DuckDB/MotherDuck. Use BaseConfig with
`MOTHERDUCK_DB = 'gme_db'` for prod, `'gme_db_dev'` for dev. dbt profiles already
support this via targets.

### 1.3 Naming Convention: `{domain}__{entity}` Double-Underscore

All table names use double-underscore to separate domain from entity:
- `order_mart__order_profile`
- `order_mart__order_item_profile`
- `order_mart__order_item_profile_partial` (intermediate)

Source tables use the pattern `{service_db}__{entity_tab}`:
- `shopee_order_v4_db__order_v4_tab`
- `shopee_order_item_v3_db__order_item_v3_tab`
- `shopee_order_logistics_db__order_logistics_tab`

**GME Applicability:** Adopt `gme_mart__fact_option_eod`, `gme_mart__dim_ticker` etc.
For raw/staging: `gme_raw__opra_quotes`, `gme_stg__enriched_quotes`.

### 1.4 Dimension Join Pattern: Build-then-Join

The `build_order_profile()` function in `order_profile_intermediate.py` shows the canonical
pattern for building a fact table from source joins:

```python
def build_order_profile(start_time, start_for_br_time, end_time, conf):
    # 1. Get base fact from transactional source
    df = get_base_order_info_from_mysqldb_tab(start_time, start_for_br_time, conf)

    # 2. Join enrichment dimensions one by one (each is a separate function)
    df = join_order_multiple_voucher_info(start_time, start_for_br_time, conf, df)
    df = join_order_return_status(df, conf)
    df = join_dim_payment_method(spark, df)
    df = join_fee_rule(spark, df, conf)

    # 3. Time conversions
    df = convert_time_cols_to_local_time(df)

    # 4. Derived columns
    df = df.withColumn('date_id', F.to_date('create_time'))

    # 5. Currency conversion (USD columns)
    usd_columns = ['total_price', 'buyer_shipping_fee', ...]
    df = add_usd_columns(spark, df.fillna(0.0, usd_columns), usd_columns, conf)

    # 6. More dimension joins
    df = add_first_purchase_column(spark, df, conf)
    df = map_cancel_reason(spark, df)

    # 7. Filter to date range
    df = filter_upto_date(df, end_time)
    return df
```

**GME Applicability:** For `fact_option_eod`:
1. Get base options data from OPRA/CBOE
2. Join `dim_ticker` for underlying attributes
3. Join `dim_date` for trading calendar info
4. Compute derived columns (implied_vol, moneyness, delta)
5. Convert to USD if multi-currency warrants involved
6. Join GEX/DIX aggregates

### 1.5 Multi-Currency Handling

Exchange rates stored in a date-partitioned dimension table:
```python
# Exchange rate dimension: dim_exrate, keyed by (grass_date, grass_region, currency)
df = df.withColumn('exrate_date_id',
    F.to_date(F.from_unixtime('event_timestamp')))  # SG timezone for exrate

usd_columns = ['total_price', 'buyer_shipping_fee', 'origin_shipping_fee', ...]
df = add_usd_columns(spark, df.fillna(0.0, usd_columns), usd_columns, conf)
```

Pattern: separate `date_id` (local timezone) from `exrate_date_id` (Singapore timezone).

**GME Applicability:** For warrants in SGD vs options in USD, maintain `dim_exchange_rate`
with daily SGD/USD rate. Apply conversion similarly.

### 1.6 Region/Country Partitioning

All tables are partitioned by `(grass_region, grass_date)`. Country-specific views
are created automatically:

```python
# Write with region+date partitioning
df.repartition('grass_region', 'grass_date') \
    .write.partitionBy('grass_region', 'grass_date') \
    .parquet(path, mode='overwrite')

# Create country-specific tables as views
for country in COUNTRY_LIST:
    country_table = 'shopee_%s.%s' % (country, table_name)
    spark.sql("CREATE TABLE %s ... path '%s/grass_region=%s'" %
              (country_table, path, country.upper()))
```

**GME Applicability:** Partition by `(market, trade_date)` where market = 'US_OPTIONS',
'SG_WARRANTS', etc. In DuckDB, use Hive-style partitioned parquet for the same effect.

### 1.7 Validation Pattern

The `order_mart_validation.py` implements a three-tier validation framework:

```python
ACCEPTABLE_THRESHOLD = 0.01  # 1% tolerance
FLOAT_ZERO = 0.0000001

# Three validation modes:
# pre_validate() -- check raw source data before processing
# partial_validate() -- check intermediate tables
# post_validate() -- check final tables

# Core check: cross-validate orderid count and GMV between fact tables
def get_total_orderid_gmv_comparison(start_date, end_date, is_partial=False):
    # Compare order_profile vs order_item_profile
    # ABS(t1.count - t2.count) / MAX(t1.count, t2.count) AS diff_percentage
    # If diff_percentage > ACCEPTABLE_THRESHOLD: FAILED
    # If 0 < diff_percentage <= ACCEPTABLE_THRESHOLD: WARNING (passed with mismatch)

# Validation states
SUCCESS_STATE = 'SUCCESS_STATE'
FAILED_STATE = 'FAILED_STATE'
PASSED_WITH_MISMATCHES_WITHIN_THRESHOLD_STATE = 'PASSED_WITH_MISMATCHES_WITHIN_THRESHOLD_STATE'
```

Key validation checks:
1. **Distinct orderid uniqueness** -- no duplicates in fact table
2. **Cross-table reconciliation** -- order_profile count matches order_item_profile distinct orderid count
3. **GMV reconciliation** -- USD GMV totals match within 1% threshold
4. **Source-to-target** -- order_profile count matches raw order_v4 count

**GME Applicability:** Critical for options DW:
1. `fact_option_eod` row count per date matches source OPRA count
2. Total open interest reconciles between fact and raw
3. No duplicate (ticker, expiry, strike, type, date) keys
4. Premium * volume totals match within threshold

### 1.8 Partition Sizing

Custom partition count per table and region to control file sizes:

```python
PARTITION_DICT = {
    'order_profile_partial_ID': 2,
    'order_profile_ID': 2,
    'order_item_profile_partial_ID': 3,
    'order_item_profile_ID': 5
}

def get_partition_number(orderid, table_name, grass_region):
    return orderid % PARTITION_DICT.get('%s_%s' % (table_name, grass_region), 1)
```

Indonesia gets more partitions because it has more data volume.

**GME Applicability:** In DuckDB/Parquet, control `row_group_size` instead. For
MotherDuck, partition parquet exports by date with target file sizes ~100-250MB.

### 1.9 Idempotent Write Pattern

```python
# Write to HDFS with overwrite mode
df.write.partitionBy('grass_region', 'grass_date').parquet(path, mode='overwrite')

# Then repair Hive metadata
spark.sql("DROP TABLE IF EXISTS %s" % table_name)
spark.sql("CREATE TABLE %s USING parquet OPTIONS (path '%s')" % (table_name, path))
spark.sql("MSCK REPAIR TABLE %s" % table_name)
```

**GME Applicability:** In dbt + DuckDB: `{{ config(materialized='table') }}` with
`on_schema_change='sync_all_columns'`. For incremental: use `unique_key` on
`(ticker_id, trade_date, strike, expiry, option_type)`.

---

## 2. keystats-daily-metrics (KPI Mart)

**What it is:** Aggregate KPI mart that produces daily metrics (total orders, GMV,
SBS orders, cross-border orders) from the order_mart fact tables.

### 2.1 DWD/DWS Layer Separation

This repo implements the Alibaba-style data warehouse layering:

| Layer | Meaning | Example Table |
|-------|---------|---------------|
| **DWD** (Data Warehouse Detail) | Cleaned, deduplicated detail records | `keystats_dwd_active_users_di` |
| **DWS** (Data Warehouse Summary) | Aggregated summaries | `keystats_dws_active_user_cnt_cm` |

```
DWD (detail, daily increment) -> DWS (summary, cumulative monthly)
```

The DWD layer stores `(grass_region, grass_date, userid)` -- one row per active user per day.
The DWS layer computes cumulative DAU/MAU from the DWD:

```sql
-- DWS: compute DAU and MAU from DWD
SELECT t1.grass_region, t1.dau, t2.mau
FROM (
    SELECT grass_region, COUNT(DISTINCT userid) AS dau
    FROM keystats_dwd_active_users_di
    WHERE grass_date = '{process_date}'
    GROUP BY grass_region
) t1
FULL OUTER JOIN (
    SELECT grass_region, COUNT(DISTINCT userid) AS mau
    FROM keystats_dwd_active_users_di
    WHERE grass_date BETWEEN '{start_of_month}' AND '{process_date}'
    GROUP BY grass_region
) t2 ON t1.grass_region = t2.grass_region
```

**GME Applicability:** For the options mart:
- **DWD layer:** `dwd_option_quotes_di` -- daily cleaned option quotes
- **DWS layer:** `dws_gex_exposure_td` -- total/cumulative GEX by date
- **DWS layer:** `dws_warrant_pnl_cm` -- cumulative monthly warrant P&L

### 2.2 KPI Aggregation Pattern

```python
# Start from the fact table (order_mart__order_item_profile)
base_report_df = get_base_report_data(start_date, end_date).cache()

# Aggregation 1: Total orders and GMV by country+date
region_order_df = base_report_df.groupBy('country', 'grass_date').agg(
    F.countDistinct('orderid').alias('total_order'),
    F.sum('gmv').alias('total_gmv')
)

# Aggregation 2: Filtered subset (SBS orders)
sbs_order_df = base_report_df.join(sku_supplier_map_df, ['itemid', 'modelid', 'grass_date'])
region_sbs_df = sbs_order_df.groupBy('country', 'grass_date').agg(
    F.sum('order_fraction').cast(LongType()).alias('total_order_sbs'),
    F.sum('gmv').alias('total_gmv_sbs')
)

# Aggregation 3: Another filtered subset (CB orders)
cb_order_df = base_report_df.filter('cb_option = 1')
region_cb_df = cb_order_df.groupBy('country', 'grass_date').agg(
    F.countDistinct('orderid').alias('total_order_cb'),
    F.sum('gmv').alias('total_gmv_cb')
)

# Final: LEFT JOIN all subsets into one wide row per country+date
write_report_df = region_cb_df \
    .join(region_sbs_df, ['country', 'grass_date'], 'left_outer') \
    .join(region_order_df, ['country', 'grass_date'])
```

**GME Applicability:** For daily options analytics mart:
```sql
-- Base: fact_option_eod
-- Agg 1: total volume/OI by ticker+date
-- Agg 2: call volume only (filter option_type='C')
-- Agg 3: put volume only (filter option_type='P')
-- Final: wide table with total_, call_, put_ prefixed columns
-- Plus: GEX = SUM(OI * gamma * spot^2 * contract_multiplier / 100)
```

### 2.3 Idempotent Incremental Write

```python
def write_to_destination_and_repair_metadata(spark, df, cold_start, date_list, directory, table_name):
    if cold_start:
        # Full overwrite
        df.write.partitionBy('grass_date').parquet(directory, mode='overwrite')
    else:
        # Write to tmp path first
        tmp_output_path = directory + 'tmp/'
        df.write.partitionBy('grass_date').parquet(tmp_output_path, mode='overwrite')

        # Delete specific date partitions from production
        for grass_date in date_list:
            hadoop_rm(directory + 'grass_date=%s' % grass_date)

        # Move from tmp to production
        move_new_data_to_production(tmp_output_path, production_path)
```

Pattern: **write-to-tmp, delete-target-partitions, move-from-tmp**. This ensures
atomicity -- if the job fails mid-write, production data is untouched.

**GME Applicability:** In dbt incremental models:
```sql
{{ config(materialized='incremental', unique_key=['ticker_id', 'trade_date']) }}
-- dbt handles the merge/delete+insert automatically
```

### 2.4 Idempotent DWD Write (Delete-Before-Append)

```python
def process_data(process_date, conf):
    # Remove existing data FIRST to assure idempotency
    remove_existing_data(process_date, conf.DWD_ACTIVE_USERS_DI_HDFS_PATH)

    # Then query and write fresh data
    df = spark.sql(query)
    df.write.partitionBy('grass_region', 'grass_date') \
        .parquet(path, mode='append')

    # Verify data landed
    check_existing_data(process_date, path)
```

**GME Applicability:** For daily option ingestion:
```sql
-- In dbt pre-hook or Python script:
DELETE FROM gme_mart.dwd_option_quotes WHERE trade_date = '{{ ds }}'
-- Then INSERT fresh data
```

### 2.5 HDFS Path Convention

```
/products/shopee/order_mart/keystats/
    dwd/active_users_di        -- detail layer
    dws/active_user_cnt_cm     -- summary layer
    cb/daily_metrics           -- KPI metrics
    sbs/map/sku_supplier       -- mapping tables
    sbs/daily_metrics          -- (deprecated)
```

Pattern: `/{org}/{domain}/{layer}/{entity}` hierarchy.

**GME Applicability:** In MotherDuck:
```
gme_db.raw.*          -- raw ingested data
gme_db.staging.*      -- cleaned/enriched
gme_db.mart.*         -- final star schema (fact + dim tables)
gme_db.analytics.*    -- KPI aggregates (GEX, DIX, warrant PnL)
```

---

## 3. daas-batch-pipelines (Aggregated Profile Pipelines)

**What it is:** Cross-domain batch pipelines that build aggregated user/item profile
tables by joining dimension tables from multiple upstream data marts.

### 3.1 DDL-as-Code Pattern

Each table's DDL is defined inline in the Python script as a string template:

```python
TABLE_NAME = 'user_segment_ads_user_features_td'

ddl = """
    CREATE EXTERNAL TABLE IF NOT EXISTS {schema_name}.{table_name}
    (
        user_id          BIGINT   COMMENT 'User ID'
        ,user_name       STRING   COMMENT 'User name'
        ,status          INT      COMMENT 'Latest User Status'
        ,gender          INT      COMMENT 'Gender'
        ...
        ,grass_date      DATE     COMMENT 'Update date yyyy-MM-dd'
    )
    COMMENT 'user profile table'
    PARTITIONED BY (grass_region STRING COMMENT 'partition key')
    STORED AS PARQUET
    LOCATION '{HDFS_PATH}/{table_name}'
"""
```

Every column has a COMMENT. The DDL is parameterized with `{schema_name}`, `{table_name}`,
`{HDFS_PATH}`.

**GME Applicability:** In dbt, this maps to model-level `description` and column-level
`description` in `schema.yml`. The discipline of documenting every column is valuable:
```yaml
models:
  - name: fact_option_eod
    description: "End-of-day option chain snapshot"
    columns:
      - name: ticker_id
        description: "FK to dim_ticker"
      - name: implied_vol
        description: "Black-Scholes implied volatility (decimal, not %)"
```

### 3.2 Wide Denormalized Profile Pattern (Star-Schema Flattening)

The `user_segment_ads_user_features_td` DML joins 10+ dimension/summary tables
into a single wide denormalized profile:

```sql
INSERT OVERWRITE TABLE {schema_name}.{table_name} PARTITION (grass_region)
SELECT
    dim_user.*,
    user_activity.last_login_datetime,
    dim_shop.shop_id, dim_shop.shop_name, ...,
    dim_seller_ext.is_power_seller, ...,
    user_interaction_td.following_cnt_td, ...,
    buyer_purchase_cat_td.all_purchased_cat_ids, ...,
    buyer_gmv_td.gmv_td AS buyer_mp_placed_order_gmv_td, ...,
    shop_listing_td.active_item_cnt, ...
FROM dim_user
LEFT JOIN user_activity ON dim_user.user_id = user_activity.user_id
LEFT JOIN dim_shop ON dim_user.user_id = dim_shop.user_id
LEFT JOIN dim_seller_ext ON dim_user.user_id = dim_seller_ext.user_id
LEFT JOIN user_interaction_td ON ...
LEFT JOIN buyer_purchase_cat_td ON ...
LEFT JOIN buyer_gmv_td ON ...
LEFT JOIN seller_gmv_td ON ...
LEFT JOIN shop_listing_td ON ...
```

This is the "One Big Table" (OBT) pattern used for downstream analytics consumption.

**GME Applicability:** For a warrant holder dashboard:
```sql
-- obt_warrant_position: wide table joining all dimensions
SELECT
    dim_ticker.*,
    dim_warrant.*,
    fact_position.quantity, fact_position.avg_cost,
    fact_eod.last_price, fact_eod.implied_vol,
    fact_gex.net_gex, fact_gex.dealer_positioning,
    dim_date.is_expiry_week, dim_date.dte
FROM fact_warrant_position
LEFT JOIN dim_ticker ...
LEFT JOIN dim_warrant ...
LEFT JOIN fact_option_eod ...
LEFT JOIN fact_gex ...
LEFT JOIN dim_date ...
```

### 3.3 Region-Aware Shard Distribution

```sql
DISTRIBUTE BY
    grass_region,
    (CASE
        WHEN grass_region='ID' THEN abs(hash(user_id)) % 128
        WHEN grass_region='BR' THEN abs(hash(user_id)) % 20
        WHEN grass_region='SG' THEN abs(hash(user_id)) % 4
        ...
        ELSE abs(hash(user_id)) % 40
    END)
```

Different regions get different shard counts based on data volume.

**GME Applicability:** In DuckDB, this is less relevant (single-node), but when
exporting partitioned parquet to S3 for MotherDuck, control file count per partition:
```sql
COPY (SELECT * FROM fact_option_eod WHERE trade_date = '2026-05-09')
TO 's3://bucket/fact_option_eod/trade_date=2026-05-09/'
(FORMAT PARQUET, ROW_GROUP_SIZE 100000)
```

### 3.4 Multi-Environment Deploy Pattern

deploy.yaml defines deployment targets per branch with `after_script` hooks:

```yaml
master:
    dest_dir: /home/jenkins/data_daasprofile/daas-batch-pipelines/master
    after_script:
        - 'bash deploy_dag.sh PROD user_segment_ads_user_gmv_1d'
        - 'bash deploy_dag.sh PROD user_segment_ads_user_features_td'

staging:
    dest_dir: .../staging
    after_script:
        - 'bash deploy_dag.sh STAGING mkt_crm_ads_user_dim'

dev_long:
    dest_dir: .../dev_long
```

**GME Applicability:** In GitHub Actions, equivalent is:
```yaml
# .github/workflows/dbt_run.yml
on:
  push:
    branches: [main]  # prod
  pull_request:       # dev/staging
```

---

## 4. shopee-item-profile (Profile/Dimension Mart)

**What it is:** Builds the `item_profile` dimension table by joining ~12 sub-dimensions
(item_basic, model_growth, order_stat, gender_pred, item_keyword, item_logistics,
seller_type, item_warehouse) into one wide denormalized item profile.

### 4.1 Phased DAG with Numbered Steps

The DAG uses numbered task prefixes for clear execution order:

```
0_start (LatestOnlyOperator)
  -> 1_require_critical_db, 1_require_item_model_v2, 1_require_item_v4
    -> 2_require_exrate
      -> 3_model_growth
        -> 4_item_basic -> 5_item_warehouse
        -> 6_order_stat -> 7_require_ads_tracking -> 8_item_keyword
        -> 9_gender_pred -> 10_item_logistics -> 12_seller_type
      -> 13_item_union (merge all sub-dimensions)
        -> 14_mark_item_profile_hdfs
          -> 15_mark_item_profile
            -> 16_send_email
```

Key concepts:
- **`require_*` tasks** = upstream dependency sensors (wait for source tables)
- **`mark_*` tasks** = success markers (signal completion to downstream)
- **`genOperator()`** = factory function that creates SSH/Dummy/Bash operator based on mode

```python
def genOperator(task_id, command, dag):
    phase_ord = int(task_id.split("_")[0])
    if phase_ord not in marked_phase:
        return DummyOperator(task_id=task_id, dag=dag)  # skip this phase
    if item_profile_mode == "live":
        return SSHOperator(task_id=task_id, ssh_hook=hook, command=command, dag=dag)
    elif item_profile_mode == "log":
        return BashOperator(task_id=task_id, bash_command='echo %s' % command, dag=dag)
```

**GME Applicability:** In dbt, this maps to model dependencies via `ref()`. The
numbered prefix pattern is useful for GitHub Actions job naming:
```yaml
jobs:
  1_ingest_raw:
  2_build_staging:
  3_build_dims:
  4_build_facts:
  5_build_analytics:
  6_run_tests:
```

### 4.2 Schema-as-Object Pattern

The `ItemBasicSchema` class encapsulates column selection, UDFs, and dimension lookups:

```python
class ItemBasicSchema(object):
    ITEM_COLUMNS = ['shopid', 'itemid', 'name', 'images', 'brand', ...]

    def __init__(self, spark):
        # Broadcast exchange rate lookup table
        exrate_by_country, exrate_by_currency = self._get_exrate_dic()
        self.bc_exrate_by_country = self.sc.broadcast(exrate_by_country)

    def udf_usd_price(self):
        exrate = self.bc_exrate_by_country.value
        def get_price_usd(price, country, currency):
            return price / exrate.get(country, 100000)
        return F.udf(get_price_usd, FloatType())

    def select_item_col(self):
        return [c.alias(n) for c, n in (
            (F.col('item.shopid'), 'shopid'),
            (F.col('item.price') / 100000.0, 'item_price'),
            (self.udf_usd_price()(F.col('item.price'), ...), 'item_price_usd'),
            ...
        )]
```

**GME Applicability:** In dbt macros, encapsulate common column transformations:
```sql
-- macros/option_pricing.sql
{% macro black_scholes_iv(price, strike, dte, rate, option_type) %}
  -- placeholder: actual IV computation in Python UDF or pre-computed
{% endmacro %}

{% macro moneyness(spot, strike) %}
  LN({{ spot }} / {{ strike }})
{% endmacro %}
```

### 4.3 Modular Sub-Dimension Build

Each sub-dimension (item_basic, item_keyword, order_stat, etc.) is a separate
Python module in `python/jobs/`. Each:
- Has its own schema definition
- Reads from specific source tables
- Writes to its own intermediate parquet path
- Gets merged into the final `item_profile` in step 13

**GME Applicability:** In dbt, use staging models as sub-dimensions:
```
models/staging/
    stg_opra__option_quotes.sql     -- raw option data cleaned
    stg_cboe__gex_data.sql          -- GEX data cleaned
    stg_ibkr__warrant_positions.sql -- warrant positions cleaned
models/intermediate/
    int_option__enriched.sql        -- options + ticker dims joined
    int_gex__by_ticker.sql          -- GEX aggregated
models/mart/
    fact_option_eod.sql             -- final fact (joins all intermediates)
    dim_ticker.sql                  -- ticker dimension
```

### 4.4 Integration Test Framework

```python
# Generic test interface
class TestBase:
    testName: str
    testPurpose: str
    def getTestResult(self) -> (str, int):  # ('PASSED'|'FAILED', exit_code)

# Available test utilities:
def rowCountTest(source_1, source_type_1, source_2, source_type_2, spark)
def duplication_test(source_1, source_type_1, spark, primary_key)
def schemaTest(source_1, source_type_1, source_2, source_type_2, spark)
def diffTest(source_1, source_type_1, source_2, source_type_2, spark)
```

**GME Applicability:** In dbt, use `dbt test` with:
- `unique` test on primary keys
- `not_null` on required columns
- `accepted_values` for option_type in ('C', 'P')
- Custom tests for row count reconciliation against source

---

## 5. user-metrics (User Metrics Aggregation)

**What it is:** Computes Chat Response Rate (CRR/CRT) metrics for sellers using
chat message data. Complex business logic with configurable thresholds.

### 5.1 DependencyMarkerSensor Pattern

Production DAGs use `DependencyMarkerSensor` to wait for upstream tables:

```python
marker_dependencies = {
    'shopee_account_v2_db__account_tab__reg_daily_s0_live': {
        'marker_name': 'marketplace.shopee_account_v2_db__account_tab__reg_daily_s0_live',
        'datetime_delta': timedelta(days=0),
        'frequency': DependencyMarkerSensor.Frequency.DAILY,
    },
    'shopee_chat_platform_db__message_tab__reg_continuous_s0_live': {
        'marker_name': 'marketplace.shopee_chat_platform_db__message_tab__reg_continuous_s0_live',
        'datetime_delta': timedelta(days=0),
        'frequency': DependencyMarkerSensor.Frequency.OTHER,
        'datatime_check_range_start': (timedelta(hours=20), True),
        'datatime_check_range_end': (timedelta(hours=44), True)
    }
}
```

In DEV, these sensors are replaced with `TimeSensor` that just waits for a specific time.

**GME Applicability:** In GitHub Actions, use workflow triggers:
```yaml
on:
  workflow_run:
    workflows: ["Ingest OPRA Data"]
    types: [completed]
```
Or in dbt, use `source freshness` checks:
```yaml
sources:
  - name: opra
    freshness:
      warn_after: {count: 24, period: hour}
      error_after: {count: 48, period: hour}
```

### 5.2 Configurable Business Logic

The config stores business-domain constants that can change independently of code:

```python
class BaseConfig:
    CRR_DAYS_TO_COVER = 90
    CRT_DAYS_TO_COVER = 30
    THRESHOLD = 2
    CRR_W = 50
    CRR_X = 25
    DEFAULT_DISPLAY_CRR = 0.57

    # Bitmask exclusion rules with effective dates
    MESSAGE_EXCLUDE_MASK = [
        ('status', 1<<13,             '2020-03-10'),  # MSG_OPT_SOCIAL_MESSAGE_FLAG
        ('status', (1<<10) | (1<<13), '2020-06-17'),  # MSG_OPT_ADS
        ('source', (1<<0) | (1<<14),  '2020-10-19'),  # AUTO_REPLY, OFFWORK_AUTO_REPLY
        ...
    ]
```

**GME Applicability:** For options analytics, store configurable parameters:
```python
# options_config.py
GEX_LOOKBACK_DAYS = 30
DIX_THRESHOLD = 0.45
WARRANT_SEED_PRICE = 0.32  # SGD per warrant
IV_SMOOTHING_WINDOW = 5    # days for IV moving average
MONEYNESS_BUCKETS = [-0.3, -0.1, -0.05, 0, 0.05, 0.1, 0.3]
```

### 5.3 Post-Processing Fan-Out Pattern

After main computation, multiple post-processing tasks run in parallel:

```python
calculate_crr >> [
    crr_chat_thread_dump,         # dump intermediate for debugging
    write_to_phoenix_table,       # write to serving layer (HBase)
    email_computation_done,       # notification
    mark_success                  # success marker for downstream
]
```

**GME Applicability:** After building fact tables:
```
dbt_run >> [
    export_to_motherduck,     # sync to cloud
    run_fact_checks,          # data quality
    generate_briefing,        # daily market briefing
    notify_operator            # Slack/email
]
```

### 5.4 Input Table Registry

Each config class declares its input tables as a dictionary:

```python
self.INPUT_TABLES = {
    'account_tab': 'marketplace.shopee_account_v2_db__account_tab__reg_daily_s0_live',
    'account_audit_tab': 'marketplace.shopee_account_extension_db__account_audit_tab__reg_daily_s1_live',
    'chat_message_tab': 'marketplace.shopee_chat_platform_db__message_tab__reg_continuous_s0_live',
    'chat_participant_tab': 'marketplace.shopee_chat_platform_db__participant_tab__reg_continuous_s0_live'
}
```

In dev/test configs, these get overridden:
```python
self.INPUT_TABLES['chat_message_tab'] = 'shopee.shopee_chat_platform_dev_db__message_tab'
```

**GME Applicability:** In dbt, use `sources` in schema.yml:
```yaml
sources:
  - name: opra_raw
    tables:
      - name: option_quotes
  - name: ibkr_raw
    tables:
      - name: warrant_positions
      - name: trade_confirmations
```

---

## 6. Star-Schema Modeling Series (Confluence Slides)

**What it is:** Internal training deck on Kimball star-schema modeling applied to
Shopee's Order Management domain.

### 6.1 Bus Matrix

The presentation defines a Bus Matrix mapping business processes to conformed dimensions.
Business processes (facts) are rows; consistency dimensions are columns. Intersections
marked where a dimension participates in that fact.

**GME Applicability:** Options DW Bus Matrix:

| Business Process | dim_date | dim_ticker | dim_option_contract | dim_exchange | dim_account |
|------------------|----------|------------|---------------------|--------------|-------------|
| Option EOD Snapshot | X | X | X | X | |
| Warrant Position | X | X | X | X | X |
| GEX Calculation | X | X | | X | |
| Trade Execution | X | X | X | X | X |

### 6.2 Fact Table Anti-Patterns

**Over-normalization:** Do NOT create a single generic `measurement_type` + `measurement_value`
fact pattern. This multiplies row count and makes ratio calculations across fact types
difficult. Keep separate columns: `premium`, `volume`, `open_interest`, `implied_vol`.

### 6.3 Role-Playing Dimensions

Same dimension appears multiple times in a fact table with different roles.
Example: date dimension as `order_date`, `ship_date`, `delivery_date`.

**GME Applicability:** In options fact table:
- `trade_date_id` -> dim_date (when the snapshot was taken)
- `expiry_date_id` -> dim_date (when the option expires)
- `last_trade_date_id` -> dim_date (last date the option traded)

In dbt:
```sql
SELECT
    f.*,
    trade_dt.is_expiry_friday AS trade_is_expiry_friday,
    expiry_dt.dte AS days_to_expiry,
    expiry_dt.is_monthly_expiry
FROM fact_option_eod f
JOIN dim_date trade_dt ON f.trade_date_id = trade_dt.date_id
JOIN dim_date expiry_dt ON f.expiry_date_id = expiry_dt.date_id
```

### 6.4 Junk Dimensions

For miscellaneous flags/indicators with small cardinality, group them into a
"junk dimension" rather than adding many foreign keys to the fact table.

**GME Applicability:** Option attributes junk dimension:
```sql
CREATE TABLE dim_option_attributes (
    option_attr_id INT PRIMARY KEY,
    exercise_style VARCHAR,     -- 'American', 'European'
    settlement_type VARCHAR,    -- 'Cash', 'Physical'
    is_weekly BOOLEAN,
    is_mini BOOLEAN,
    is_adjusted BOOLEAN,
    is_non_standard BOOLEAN
)
```
One FK in fact table instead of 6 separate boolean columns.

### 6.5 Multi-Currency Handling

Store both local currency and standardized USD amounts as separate columns in the
fact table. Do NOT create separate fact rows per currency.

```
-- Fact columns:
premium_local      -- in local currency (SGD for warrants)
premium_usd        -- converted to USD
fx_rate_used        -- the rate applied (for audit trail)
```

### 6.6 Mixed-Granularity Facts

When some metrics exist at order level but analysis needs order-item level,
allocate the order-level metric proportionally:

**Bad patterns:**
1. Repeat the order-level amount on every line item (double-counting)
2. Put it only on the first/last line item (arbitrary)
3. Use a magic key (key=99999)

**Good pattern:** Allocate proportionally based on line item's share of total.

**GME Applicability:** When warrant costs (brokerage, stamp duty) are at order level
but analysis is at contract level, allocate proportionally by contract value.

### 6.7 Accumulating Snapshot Fact Table

For processes with a lifecycle (order placed -> shipped -> delivered -> completed),
use an accumulating snapshot: one row per order, with date columns for each milestone.
Update the row as milestones are reached.

Three physical implementations:
1. **Full-volume update:** Rebuild all historical data daily (expensive)
2. **Partial full-volume:** Only update orders from last N days (Shopee uses 64 days)
3. **Incremental with partition by end-time:** Most efficient, needs changelog/binlog

**GME Applicability:** For warrant lifecycle tracking:
```sql
CREATE TABLE fact_warrant_lifecycle (
    warrant_id,
    purchase_date,        -- milestone 1
    first_itm_date,       -- milestone 2 (first in-the-money)
    exercise_date,        -- milestone 3
    settlement_date,      -- milestone 4
    current_status        -- 'OPEN', 'EXERCISED', 'EXPIRED', 'SOLD'
)
```
Use the 64-day partial rebuild pattern: only reprocess warrants with activity in last 64 days.

---

## 7. Automatic DB Ingestion (Confluence Slides)

**What it is:** Internal presentation on Shopee's automated database ingestion system.

### 7.1 Ingestion Architecture Components

1. **Job Management** -- auto-generates Spark configs, Airflow DAGs, GitLab PRs
2. **Job Profiling** -- maintains lifecycle and metadata for each ingestion job
3. **Configuration Service** -- manages live job configs (not in git, too volatile)
4. **Automatic Adaptation** -- rules-based parameter tuning (resources, partitions, start times)
5. **Automatic Operation** -- APIs for monitoring, priority, alerting

### 7.2 Job Profiling Schema

Each ingestion job tracks:
- Basic Information (table name, schema, source)
- Runtime Information (last run, duration, status)
- Table Information (row count, size, partitions)
- Job Configurations (Spark params)
- Running History
- Resource Consumption History
- Change History
- Queue Status

**GME Applicability:** For the options DW, maintain an ingestion metadata table:
```sql
CREATE TABLE meta_ingestion_jobs (
    job_id VARCHAR PRIMARY KEY,
    source_name VARCHAR,           -- 'opra_api', 'cboe_csv', 'ibkr_flex'
    target_table VARCHAR,          -- 'raw.opra_quotes'
    last_run_at TIMESTAMP,
    last_run_status VARCHAR,       -- 'SUCCESS', 'FAILED', 'RUNNING'
    rows_ingested BIGINT,
    run_duration_seconds INT,
    last_error_message VARCHAR,
    config_json JSON               -- ingestion parameters
)
```

### 7.3 Automatic Adaptation Rules

Key insight: ingestion jobs run at night, humans make mistakes, so encode rules:
- Auto-adjust Spark resources based on table size
- Auto-adjust partition keys based on data distribution
- Auto-adjust start times based on upstream completion
- Auto-set priority based on downstream dependencies

**GME Applicability:** For daily option data ingestion:
- If OPRA API fails, retry with exponential backoff
- If data volume differs >20% from previous day, alert
- If market was closed (holiday), skip ingestion gracefully
- Adjust ingestion window based on data availability time

---

## Cross-Cutting Patterns Summary

### Pattern Catalog for GME Options DW

| # | Pattern | Shopee Source | GME Application |
|---|---------|---------------|-----------------|
| 1 | Three-phase DAG (dims -> staging -> facts) | cube-prepare | dbt model layers |
| 2 | BaseConfig with env overrides | ALL repos | dbt profiles + env vars |
| 3 | `domain__entity` naming | cube-prepare | `gme_mart__fact_option_eod` |
| 4 | Build-then-join fact construction | cube-prepare | dbt ref() chain |
| 5 | DWD/DWS layer separation | keystats | staging/mart in dbt |
| 6 | Aggregate by filter subsets | keystats | call/put/total aggregates |
| 7 | Write-to-tmp then swap | keystats | dbt incremental strategy |
| 8 | DDL-as-code with column comments | daas-batch | dbt schema.yml |
| 9 | Wide denormalized OBT | daas-batch | obt_warrant_position |
| 10 | Numbered task phases | item-profile | GitHub Actions job ordering |
| 11 | Schema-as-object for UDFs | item-profile | dbt macros |
| 12 | Modular sub-dimension build | item-profile | dbt staging models |
| 13 | Integration test framework | item-profile | dbt test + custom tests |
| 14 | DependencyMarkerSensor | user-metrics | source freshness checks |
| 15 | Input table registry | user-metrics | dbt sources |
| 16 | Bus matrix planning | slides | dimension conformity |
| 17 | Role-playing dimensions | slides | trade_date vs expiry_date |
| 18 | Junk dimensions | slides | dim_option_attributes |
| 19 | Multi-currency columns | slides + cube-prepare | premium_local + premium_usd |
| 20 | Accumulating snapshot | slides | fact_warrant_lifecycle |
| 21 | Partial rebuild (64-day window) | slides | incremental with lookback |
| 22 | Pre/partial/post validation | cube-prepare | dbt test stages |
| 23 | Threshold-based pass/warn/fail | cube-prepare | custom dbt tests |
| 24 | Configurable business params | user-metrics | dbt vars / project vars |
| 25 | Post-processing fan-out | user-metrics | dbt post-hooks + GHA |
| 26 | Ingestion metadata tracking | auto-ingestion slides | meta_ingestion_jobs |

### Priority Actions for GME Mart

1. **Immediate:** Adopt naming convention `gme_mart__fact_*`, `gme_mart__dim_*`
2. **Immediate:** Add column descriptions to all dbt schema.yml files
3. **Next sprint:** Implement three-tier validation (source count, uniqueness, cross-table reconciliation)
4. **Next sprint:** Build `dim_date` with role-playing support (trade_date, expiry_date)
5. **Next sprint:** Add `meta_ingestion_jobs` table for pipeline observability
6. **Future:** Implement accumulating snapshot for warrant lifecycle tracking
7. **Future:** Build OBT for warrant dashboard consumption

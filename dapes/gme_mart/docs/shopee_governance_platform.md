# Shopee Data Governance, Platform Architecture & Hourly Mart Design

> Extracted from three internal Shopee documents for Kimball DWH pattern reference.
> Date: 2026-05-09

---

## Source 1: Data Governance Phase 1 (Ownership and Access Control)

### Team & Contact

- **Data Governance Team:**
  - Tan Siyuan (tansy@sea.com)
  - Sophie Gao (gaosh@sea.com)
  - Ivan Soh (ivan.soh@shopee.com)
- **Charter:** Define and enforce policies within the big data ecosystem:
  - Data security, data usability, data integrity for accurate, reliable, secure usage
  - Resource management for computational and storage resources among users and producers

---

### Background: Problems with Common Schemas

**Common Schemas** (e.g., `shopee(_xx)(_s1+)`, `seamoney(_xx)(_s1+)`) had compounding problems:

| Stakeholder | Problems |
|-------------|----------|
| **Data Users** | Hard to identify needed tables; hard to use without column explanation or PIC information |
| **Data Producers** | Hard to encourage mart usage; many users still used raw ingested tables |
| **Data Security** | Schema-level access too broad; users had access to data they did not need |
| **Resource Management** | Hard to deprecate tables without owner info; no table lifecycle management, causing resource waste |

**Fragmented Schema-level Access Control Problems:**

- Access control not synchronized across products, requiring multiple applications
- Schema-level control led to unnecessary data access: access to "shopee" schema = access to 15,000+ tables
- Many schemas created solely to control access to a few tables

---

### Objectives

1. **Clear data ownership** -- table in project schema, team responsible for metadata/lifecycle, users know who owns tables, easier to choose trusted tables
2. **Centralised table-level access control** -- more granular/flexible access, no need to create schema just for access control, apply once and take effect in all data products

---

### Execution Plan (4 Stages)

#### Stage 1: Team & Project Initialisation (Jun 2021, 1 month)

- Consolidate and initialise teams/projects in Data Suite
- Collect team/project information for RAM (Resource & Access Management) initialisation
- Structure: Team -> Team Admin(s) -> Project Name -> Project Code -> Project Admin(s) -> Project Schemas

**Example:**

| Team | Team Admin | Project Name | Project Code | Project Admin | Project Schema |
|------|-----------|-------------|-------------|--------------|----------------|
| SG BI | Jin Hui (jinh@sea.com) | Project 1 | sgbi_proj1 | hongjie.li@shopee.com | sgbi_proj1 |

#### Stage 2: Claim Table Ownership & Double-Writing (Jul-Sep 2021, 2 months)

- Team/project admins claim table ownership and provide new table names in new schema
- All existing jobs must double-write to both old and new schemas
- Data Infra handles ingestion and Data Nexus jobs
- All producers handle PrestoJDBC and Spark jobs manually

**Table Mapping Example:**

| Old Schema | Old Table Name | New Schema | New Table Name |
|-----------|---------------|-----------|---------------|
| shopee | order_mart__order_profile | marketplace | reg_order_mart__order_profile |
| shopee | shopee_reg_bi_team__abc_1 | regbi_proj | abc_1 |
| shopee_sg | order_mart__order_profile | marketplace | sg_order_mart__order_profile |

#### Stage 3: Table-level Access Control & Read New Tables (Sep-Dec 2021, 4 months)

- Enforce table-level access control for all users
- Initialise all users into two access groups:
  - **Common access group**: data marts + commonly used BI-generated tables
  - **Raw access group**: commonly used ingested raw tables
- Users must apply separately for:
  - Sensitive (s1+) tables
  - Tables in private schemas
- SQL migration tools provided:
  - **Data Nexus**: automated conversion tool
  - **Lumos**: team-by-team SQL asset migration after user authorization
  - **PrestoJDBC/SparkSQL**: self-service SQL conversion webpage
- Migration progress tracking via query count monitoring on old tables
- Stop new table creation on old schemas

**Schema Restructuring (Before -> After):**

| Before | After |
|--------|-------|
| Common Schemas (shopee(_xx)(_s1+), seamoney(_xx)(_s1+)) | Data Mart Schemas (marketplace, credit, shopeepay) |
| Private Schemas (shopee_sg_anlys, shopee_reg_antifraud_anlys) | BI Private Schemas (sgbi_proj, regbi_proj) |
| (mixed in common) | Business Line Private Schemas (antifraud, smcdrisk_policy) |

#### Stage 4: Retire Old Schema (Jan 2022, 1 month)

- Retire all tables in old common schemas (including unclaimed raw ingested tables)
- Retire all tables in old private schemas
- Outcome: all tables migrated to new schemas with clear ownership, fully table-level access control
- Phase 2 planned: move users from reading ingested tables to data marts, tighten table accesses

---

### Team-Project Model (Appendix)

**Hierarchy:**

```
Data Infra Products & Services
  |-- Team 1
  |     |-- Team PIC (manages members, applies resources)
  |     |-- Project A
  |     |     |-- Project Admin (manages members, owns data + jobs)
  |     |     |-- Data: hive tables, hbase tables, kafka topics
  |     |     |-- Resources: service account, hive schema, HDFS directory
  |     |     |-- Compute: Spark YARN queue, Presto SQL resource queue
  |     |-- Project B
  |-- Team 2
        |-- Project C
        |-- Project D
```

**Key principle:** Hive tables are stored in one project schema per project. All online data jobs run by service account. HDFS directory and hive schema store project data and files.

**Example (Team 1):**

- Team PIC manages Alice, Bob, Dylan, Cindy
- Project A: Admin = Alice, Bob; Members = Cindy, Dylan
- Project B: Admin = Cindy; Member = Bob
- Each project gets its own: service account, hive schema, HDFS directory

---

### Table-level Access Control Principles & Data Classifications

**Principles:**

1. Data access controlled at table level (for hive tables), centrally managed in Data Suite
2. Access strictly segregated by country (SG user cannot access TW data unless explicitly approved)
3. By default, a user only has read access to tables of their own project; all other access must be applied or assigned

**Data Classifications:**

| Dimension | Categories | Details |
|-----------|-----------|---------|
| **Public vs Private** | Public = data mart tables manually marked by mart teams (s1+ excluded); Private = all others |
| **Insensitive vs Sensitive** | s0 = non-sensitive; s1/s2/s3 = sensitive, postfix in table name (e.g., `marketplace.reg_user_address_s1`) |
| **Regional vs Local** | Regional: `marketplace.reg_order_mart_dwd_tab`; Local: `marketplace.sg_order_mart_dwd_tab` |

**Naming Convention:**

- Schema = business domain (marketplace, credit, shopeepay) or team project code (sgbi_proj, regbi_proj)
- Table prefix = region code (reg_, sg_, tw_, vn_, etc.)
- Table suffix = sensitivity level (_s0, _s1, _s2, _s3)

---

### Access Application Process

1. Data users apply for table access in Data Suite (Resource & Access Management)
2. Approvers approve application tickets in SOUP
3. Once approved, users can access the table regardless of which data product they use (unified access)

### Access Groups

- **Global Access Groups**: Created by Data Infra, used by project admins, applied to project members
  - Cover public tables marked by data mart teams
  - Named by pattern: `Public_marketplace_reg`, `Public_marketplace_xx`, `Public_credit_reg`, etc.
- **Customised Access Groups**: Created by project admins for commonly used tables
  - Configured per project, applied to project members
  - All sensitive (s1+) tables CANNOT be added into access groups

---

### Impact Matrix by Team Type

**Data Mart Teams:**

| Stage | Actions |
|-------|---------|
| Stage 1 | Confirm team/project/schema info; add members |
| Stage 2 | Claim table ownership; provide mapping list; double-write Spark jobs; designate common access group tables |
| Stage 3 | Modify Spark scripts to read new tables |
| Stage 4 | Ensure Spark jobs stop updating old tables |

**BI Teams:**

| Stage | Actions |
|-------|---------|
| Stage 1 | Confirm team/project info; add members |
| Stage 2 | Claim ownership; mapping list; double-write PrestoJDBC/Spark; designate common access group |
| Stage 3 | Use Data Nexus conversion tool; authorize Lumos SQL conversion; use SQL conversion webpage; apply access for private/sensitive tables |
| Stage 4 | Ensure PrestoJDBC/Spark jobs stop updating old tables |

**Business Line Teams:**

| Stage | Actions |
|-------|---------|
| Stage 1 | Confirm team/project info; add members |
| Stage 2 | Claim ownership; mapping list; double-write PrestoJDBC/Spark |
| Stage 3 | Use Data Nexus/Lumos/SQL conversion webpage; apply access for private/sensitive tables |
| Stage 4 | Ensure PrestoJDBC/Spark jobs stop updating old tables |

---

## Source 2: Shopee iData Platform for DE (Confluence, Apr 2019)

### Platform Overview

- **Scale:** 2,400+ servers, 23,000+ tables, 22PB+ data, 20,000+ daily jobs, 60,000+ daily queries
- **Infrastructure:** 38,480 Vcore, 586TB processing power, 110PB+ storage
- **Hadoop big data ecosystem**, 2 locations: SG and ID
- **Real-time data delay:** 99% < 30s
- **Offline data delay:** Ready by 10am (noted as needing improvement)
- **Query capacity:** Million data < 1s

### Platform Architecture Evolution

#### v1.0 (2017): Initial Data Infra

```
Sources: LOG (rsync) + MySQL (spark)
  --> Data Cluster: SPARK + Hadoop
  --> ETL --> Redshift
Scheduling: Oozie
Ops: Ansible + Zabbix
```

#### v1.1 (2018): Added Presto

```
Sources: LOG (rsync) + MySQL (spark)
  --> Data Cluster: Presto + SPARK + Hadoop
  --> ETL --> Redshift
Scheduling: Oozie
Ops: Ansible + Zabbix
```

#### v2.0 (2018): Added Real-time Pipeline

```
Sources: MySQL, Log, CSV, Google Sheet, EL, Third party

Real-time Pipeline:
  MySQL --Kafka--> Spark stream
  MySQL --Maxwell--> HBase
  --> Druid

Batch Pipeline:
  All sources --Spark/API--> Data Cluster (Presto, HBase, SPARK, Hadoop)
  --> ETL --> Redshift

Scheduling: Oozie
Ops: Ansible + Zabbix
```

#### v2.1 (2018): Modernised Orchestration + Monitoring

```
Sources: MySQL, Log, CSV, Google Sheet, EL, Third party

Real-time Pipeline:
  MySQL --Kafka--> Spark stream
  MySQL --Maxwell--> HBase
  --> Druid

Batch Pipeline:
  All sources --Spark/API--> Data Cluster (Presto, HBase, SPARK, Hadoop)
  --> ETL --> Druid

Scheduling: Airflow (replaced Oozie)
Ops: Ambari + Ansible, ELK Log, Tick + Grafana monitor
```

#### v2.2 (2018): Added Query Engine + Data Products Layer

```
Sources: MySQL, Log, CSV, Google Sheet, EL, Third party

Real-time Pipeline:
  MySQL --Kafka--> Spark stream
  MySQL --Maxwell--> HBase
  --> Druid

Batch Pipeline:
  All sources --Spark/API--> Data Cluster (Presto, HBase, SPARK, Hadoop)
  --> ETL --> Druid + Kylin

Output Layer:
  API service --> Data product
  Query engine --> Live product

Scheduling: Airflow
Ops: Ambari + Ansible, ELK Log, Tick + Grafana monitor
```

### Data Warehouse Layer (Pyramid Architecture)

```
             Application Data (top)
             - Lumos (BI dashboards)
             - Insight (self-service query)
             - Brand Portal, Seller Center
             - DA, DS, Other team apps

             Data Mart (middle)
             - Order, Paid Ads, Item
             - User, User Behavior, Traffic/Conversion
             - FlashSales, Microsite, Collection

             Raw Data (bottom)
             - mysql db, log, csv
             - Google-sheet, rest api, other

Side pillars: Data Quality + Data Monitor
```

### Data Sources at Shopee

**User Journey touchpoints generating data:**

1. Shopee Homepage / Third-party website
2. Search Page
3. Product Page
4. Buy Now or Add-to-cart
5. Order Placement
6. Seller Shipment
7. Express/Logistics/Delivery
8. Confirmation / Return/Refund
9. Order Complete

**Data Categories:**

| Type | Examples |
|------|----------|
| Transaction | Orders, payments, refunds |
| Logistics | Shipment, delivery, 3PL |
| User Behavior | Clicks, impressions, views |
| Customer Service | Tickets, inquiries |
| Features & Applications | Paid ads, WMS, SBS, Seller Center |
| Third-Party Data | Competitive intelligence, Appsflyer & GA tracking |
| User-maintained Data | Business targets, campaign info |

### Infrastructure Challenges

- Serious performance issues with growing clusters (Namenode performance, HBase RS)
- Lack of manpower on daily operations
- Data quality and monitoring not good enough
- MySQL daily ingestion not stable; could not meet hourly ingestion requirements
- 70% of users still using raw data instead of data marts

### Input Data Products (Ingestion/Processing)

| Tool | User Group | Purpose |
|------|-----------|---------|
| **Auto-ingestion** | BI, Product Team | User-friendly automatic ingestion into DWH |
| **Data Tracking** | BI, Product, Business | SDK for user behavior tracking (iOS, Android, PC; Shopee, Seller Center) |
| **Data Process (Spark + Airflow)** | DE, DS, BI, Developer | Big data processing and task execution flow |
| **Data Nexus (Spark + Airflow)** | DE, DS, BI, Developer | One-stop data development platform: reports, pipeline dev. Phase 1: Presto compute, Table/XLS/CSV output, Email/Screenshot notify |
| **Profile Pool** | DE, DS, BI, Developer | Self-service batch/real-time column creation for profile tables (no GTS ticket needed) |
| **Data Map** | All | General table details (status, PIC, application) for query and management |

**Data Tracking SDK Details:**

- Support: who (userid, deviceid), when (event_timestamp), where (country, ip), how (os, device, app_version, channel_source), what (login, register, view, impression, click, add_item_cart, placeorder)

### Output Data Products (Consumption)

| Product | Target Users | Key Features |
|---------|-------------|-------------|
| **Lumos** | SQL Analysts | SQL Lab workspace, data visualization library, data preprocessing system |
| **Insight Query Builder** | BD, MKT, OM | Point-and-click design, result preview/download, job scheduling (no SQL required) |
| **Insight Campaign Station** | CMs, MKT Campaign | Minute-by-minute KPI updates, performance benchmarking, daily target setting |
| **Brand Portal** | External Brands, KAMs | Custom category trees, seller-specific metrics, seller-managed ACL |

---

## Source 3: Order Mart Hourly Design

### Context & Problems

**Current key problems with order_mart hourly tables:**

1. **Latency issues:** Campaign day ingestion + job pipeline delays up to 5 hours due to huge data surge
2. **Update limit of 7 days:** Only orders created within 7 days available in hourly table
3. **Missing columns** compared to daily table

### Two Key Use Cases

1. **D0 (Day-0) analysis and monitoring:**
   - D0 PRM cost and GMV/order monitoring
   - D0 fraud order tracking
   - D0 order fulfilment / 3PL allocation analysis

2. **Daily ops monitoring:**
   - Hourly update of order status / logistics status of ongoing orders for operational needs

### Pipeline Improvement

**Old Pipeline (for "how many orders placed between 9-10 am"):**

- Ingestion window: 15 min to 11 hours
- Data processing: 45 min to 1.5 hours
- Data available: 11:25 am to 8 pm (worst case)
- Schedule start: 10:40 am

**New Pipeline:**

- Ingestion: est. 15 min to 2 hours
- Data processing: est. 30 min to 1 hour
- Data available: 10:45 am to 1 pm
- Schedule start: Immediately after ingestion completes (no scheduled delay)

### Hourly Table Catalog

| Table Name | Logic | Retention |
|-----------|-------|-----------|
| `mp_order.hourly_dwd_order_place_pay_complete_tch__{cid}_s0_live` | All orders with metric changes within the day. Partitioned by grass_date. Filter via is_placed, is_paid, is_completed, is_cancelled flags. | 3 days (including D0) |
| `mp_order.hourly_dwd_order_item_place_pay_complete_tch__{cid}_s0_live` | Order-item level of same logic as above. Same filtering flags. | 3 days (including D0) |
| `mp_order.hourly_dwd_order_item_subset_all_ent_hf__{cid}_s0_live` | All non-terminated orders (9999-01-01 partition of daily) + D0 orders. | 3 days (including D0) |

All other hourly tables not listed are NOT meant for external usage.

### TCH (Till Current Hour) Table Design

**How it works:** Contains all orders created on D0 AND orders created within 365 days that had updates within the past 2 days from D0.

**Schema example (`hourly_dwd_order_place_pay_complete_tch`):**

| Column | Description |
|--------|------------|
| order_id | Order identifier |
| create_datetime | When the order was created |
| order_be_status | Current backend status (PAID, ESCROW_PAID, CANCEL_COMPLETED, etc.) |
| is_placed | Flag: 1 if order was placed in this grass_date partition |
| is_paid | Flag: 1 if order was paid in this grass_date partition |
| is_complete | Flag: 1 if order was completed in this grass_date partition |
| is_cancelled | Flag: 1 if order was cancelled in this grass_date partition |
| grass_date | Partition date -- the date the metric change happened, NOT the order creation date |

**Critical design detail:** The same order_id can appear in MULTIPLE grass_date partitions. For example:
- Order 11223445 created 2022-03-14, paid 2022-03-14 -> appears in grass_date=2022-03-14 with is_placed=1, is_paid=1
- Same order completes (ESCROW_PAID) on 2022-03-16 -> appears in grass_date=2022-03-16 with is_completed=1

### HF (Hourly Full) Table Design

**How it works:** Contains all orders terminated in the past 2 days (grass_date = t-2, t-1, t-0) AND all non-terminated orders (grass_date = 9999-01-01).

**Schema adds:** order_id, item_id, model_id, bundle_order_id, group_id, create_datetime, order_be_status, grass_date

**Key difference from TCH:** HF is a subset table containing partial data -- to get complete order list, union with daily table (minus 9999-01-01 partition).

**Complete order list formula:**

```
Complete = HF table (non-terminated + recent terminated)
         UNION ALL
         Daily table (grass_date > lookback AND grass_date < CURRENT_DATE - 1 day)
```

### Order Lifecycle Flow (TCH Flags)

```
Order Placement --> Order Payment --> Order Fulfillment --> Order Complete --> Escrow
```

- **is_placed=1**: order was placed on that grass_date
- **is_paid=1**: order was paid on that grass_date
- **is_completed=1**: order completed on that grass_date
- **is_cancelled=1**: order was cancelled on that grass_date

An order placed 2 days ago but completed today will appear in today's partition with is_completed=1 only (not is_placed).

### Sample Query (TCH)

```sql
-- How many orders placed between 9-10 am?
SELECT
    Hour(From_unixtime(create_timestamp), 'asia/jakarta'),
    SUM(gmv),
    SUM(pv_rebate_by_shopee)
FROM mp_order.hourly_dwd_order_place_pay_complete_tch__id_s0_live
WHERE grass_date = DATE'2020-12-12'
  AND is_placed = 1
GROUP BY 1
```

### Sample Query (HF -- Complete Order List)

```sql
WITH order_total AS (
    -- Historical terminated orders from daily table
    SELECT order_id, item_id, model_id, group_id, bundle_order_item_id, gmv
    FROM mp_order.dwd_order_item_all_ent_df__reg_s0_live
    WHERE grass_region = 'SG'
      AND grass_date > CURRENT_DATE - interval '64' day
      AND grass_date < CURRENT_DATE - interval '1' day

    UNION ALL

    -- Recent + non-terminated from hourly table
    SELECT order_id, item_id, model_id, group_id, bundle_order_item_id, gmv
    FROM mp_order.hourly_dwd_order_item_subset_all_ent_hf__sg_s0_live
    WHERE grass_region = 'SG'
)
SELECT ...
```

### Missing Columns (TCH vs Daily v2)

The hourly TCH table is missing these columns present in the daily table:

- campaign_discount / campaign_discount_usd
- coin_earn_rule_id
- free_shipping_voucher
- brand
- price_before_bundle
- shopee_actual_shipping_rebate
- ASF (additional seller fee)
- shopee_coin_rebate / shopee_coin_rebate_usd

### Known Limitations

1. **T-1 dimension denormalization:** Some dimension joins use T-1 data, causing slight variation vs daily table:
   - Shop dimension: < 0.1% impact
   - Buyer dimensions: ~1-2% for SEA+TW, 9% for BR
   - Logistic promotions (affects estimated shipping rebate): 0% impact
2. **Late-arriving data:** If a joined table hasn't ingested in time, values remain NULL until next hour update
3. **Retention:** Only 3 days of changes kept (including D0)

---

## Patterns Applicable to Kimball DWH Design

### 1. Data Ownership Model

**Shopee Pattern:** Hierarchical Team -> Project -> Schema -> Table ownership

| Concept | Shopee Implementation | Kimball DWH Equivalent |
|---------|----------------------|----------------------|
| Team | Organizational unit (SG BI, Marketplace) | Data domain / subject area |
| Project | Work unit within team, owns data + jobs | Schema / data product |
| Table owner | Project admin responsible for metadata + lifecycle | Fact/dim table steward |
| PIC (Person In Charge) | Named individual per table | Data steward per model |

**Applicable lesson:** Every table needs a named owner. Without it, you cannot deprecate tables, enforce lifecycle, or build trust. At Shopee, lack of ownership led to 15,000+ unmanageable tables in a single schema.

### 2. Access Control Patterns

**Shopee Pattern:** Table-level ACL with classification dimensions

| Dimension | Shopee | Applicable to GME Mart |
|-----------|--------|----------------------|
| Sensitivity tiers | s0/s1/s2/s3 suffix in table name | Public vs restricted (PII, position data) |
| Regional segregation | Country-level isolation (sg_, tw_, reg_) | N/A for single-market, but relevant for multi-account |
| Public vs private | Data mart = public; team tables = private | Mart tables vs staging/raw |
| Access groups | Global (curated marts) + Custom (team-specific) | Role-based groups (analyst, ops, admin) |
| Unified access | Apply once in Data Suite, works across all products | Single ACL layer regardless of query tool |

**Key takeaway:** Schema-level access is too coarse. Table-level with sensitivity classification and role-based groups is the right granularity. The "apply once, works everywhere" principle is critical for multi-tool environments.

### 3. Platform Architecture Components

**Shopee's evolved stack:**

| Layer | Components | GME Mart Equivalent |
|-------|-----------|-------------------|
| Ingestion | Auto-ingestion, Kafka, Maxwell CDC, Spark/API, rsync | httpfs + Python ingest scripts |
| Storage | Hadoop HDFS, HBase, Hive | DuckDB / MotherDuck |
| Processing | Spark (batch), Spark Streaming (real-time), Airflow (orchestration) | dbt (batch), GitHub Actions (orchestration) |
| Query | Presto (interactive SQL), Druid (real-time OLAP), Kylin (pre-aggregation) | DuckDB direct query |
| Serving | Redshift (analytical), Druid (live dashboards), Lumos (BI) | MotherDuck (analytical) |
| Metadata | Data Map (table catalog with PIC/status/docs) | dbt docs + schema.yml |
| Self-service | Data Nexus (SQL dev), Profile Pool (column creation), Insight Query Builder | N/A (single-user) |
| Monitoring | Zabbix -> ELK Log + Tick + Grafana | dbt test + fact_check.py |

### 4. Hourly vs Daily Granularity Decisions

**Shopee's approach -- keep both, designed for different use cases:**

| Aspect | Hourly (TCH/HF) | Daily |
|--------|-----------------|-------|
| Use case | D0 monitoring, real-time ops | Historical analysis, complete data |
| Completeness | Subset (3-day window) | Full history |
| Dimension quality | T-1 dimensions (1-9% variance) | Current dimensions |
| Column coverage | Missing campaign/promo columns | Full column set |
| Partition key | grass_date (event date, not creation date) | grass_date (final status date) |
| Retention | 3 days | Full |

**Critical design decisions:**

1. **Separate tables for hourly vs daily** -- NOT a single table with different refresh rates. The data model differs (hourly has event flags, daily has final states).
2. **grass_date = event date in hourly, final date in daily** -- same column name, different semantics. This is the key to the TCH pattern: partition by "when did this change happen" not "when was the order created."
3. **Union pattern for complete view** -- hourly HF + daily (minus overlap window) gives complete picture. Documented explicitly with sample SQL.
4. **Accept dimension staleness** -- T-1 dimensions are explicitly documented as acceptable for hourly use cases. Don't block hourly pipeline waiting for dimension refresh.
5. **Flag-based design (is_placed, is_paid, is_completed, is_cancelled)** -- instead of storing status history, use boolean flags per partition to indicate what changed. This avoids complex SCD logic for real-time tables.

**Applicable lesson for GME Mart:** If hourly granularity is needed for options/warrant monitoring:
- Keep daily mart as primary (complete, all columns)
- Add a separate hourly/intraday table with reduced columns and event-based flags
- Document missing columns and dimension variance explicitly
- Use union pattern to combine hourly + daily for complete views

### 5. Metadata Management

**Shopee's metadata stack:**

| Component | Purpose |
|-----------|---------|
| **Data Map** | Central table catalog: table status, PIC, column descriptions, data lineage |
| **Data Suite (RAM)** | Resource & Access Management: team/project membership, access groups, table-level ACL |
| **SOUP** | Approval workflow for access tickets |
| **Data Nexus** | SQL development platform with built-in SQL conversion tools |
| **Profile Pool** | Self-service column/metric definition without engineering tickets |

**Naming conventions (enforced):**

- Schema = business domain or team project code
- Table prefix = `reg_` (regional) or country code (sg_, tw_, vn_)
- Table suffix = sensitivity level (_s0, _s1)
- Table type prefix in name = `dwd_` (detail), `dws_` (summary), `ads_` (application)
- Hourly marker = `hourly_` prefix
- Live marker = `_live` suffix
- Country placeholder = `__{cid}_` in table name template

### 6. Migration Strategy (Schema Restructuring)

**Shopee's 4-stage migration is a reference for any DWH restructuring:**

1. **Initialize ownership** (1 month) -- get humans to claim teams/projects/schemas
2. **Double-write** (2 months) -- write to both old and new schemas simultaneously
3. **Migrate readers + enforce new access** (4 months) -- gradual cutover with tooling support
4. **Retire old schemas** (1 month) -- hard cutoff after migration verified

**Key enablers:**
- SQL conversion tooling (automated where possible, self-service where not)
- Migration progress tracking via query count on old tables
- Stopping new table creation on old schemas before full retirement
- Access group bootstrapping so users don't lose access during transition

---

## Table Naming Convention Reference

From the three sources combined, Shopee's naming convention:

```
{schema}.{region}_{domain}_{layer}_{entity}_{grain}_{qualifier}__{country_id}_{sensitivity}_live

Examples:
  marketplace.reg_order_mart_dwd_tab
  marketplace.sg_order_mart_dwd_tab
  mp_order.hourly_dwd_order_place_pay_complete_tch__id_s0_live
  mp_order.dwd_order_item_all_ent_df__reg_s0_live
  mp_order.hourly_dwd_order_item_subset_all_ent_hf__sg_s0_live
```

**Decomposition:**
- `mp_order` = schema (marketplace order domain)
- `hourly_` = refresh cadence
- `dwd_` = data warehouse detail layer
- `order_item_` = entity
- `place_pay_complete_` = metrics included
- `tch` / `hf` / `df` = table type (Till Current Hour / Hourly Full / Daily Full)
- `__id` / `__sg` / `__reg` = country scope
- `_s0` = sensitivity classification
- `_live` = production table marker

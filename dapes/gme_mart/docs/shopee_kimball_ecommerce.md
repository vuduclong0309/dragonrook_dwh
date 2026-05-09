# Shopee Kimball E-Commerce Modeling: Extracted Patterns

Source presentations from Shopee's internal Kimball dimensional modeling training series.
Extracted 2026-05-09 for GME Mart reference architecture.

---

## 1. Kimball Model Sharing -- Electronic Commerce (Part 1)

**Source:** `E:\Shopee\Shopee Slide Archive\Kimball Model Sharing - Electronic Commerce .pptx`
**Slides:** 9 | **Topic:** Clickstream dimensional modeling for e-commerce (Kimball Ch. 15)

### 1.1 Clickstream Data Overview

Clickstream data records every web visitor gesture at the most elemental level: every page event recorded by each web server. It introduces dimensions not found in other data sources: **page, session, referrer**.

Data sources:
- Server log files
- Referring partners
- Search engine specifications

Key challenges:
- **Identifying the visitor:** persistent cookies vs. session-level cookies; visitors want anonymity and may provide inaccurate information
- **Identifying the session:** associating time-contiguous log entries from the same host
- **Identifying visitor origin:** search portals, browser bookmarks, text/graphical links from other sites

### 1.2 Dimension Catalog for Web Retailer

The full list of dimensions for a web retailer clickstream model:

| Dimension | Category |
|-----------|----------|
| Date | Standard |
| Time of Day | Standard |
| Product | Conformed |
| Customer | Conformed |
| Page | Clickstream-specific |
| Event | Clickstream-specific |
| Session | Clickstream-specific |
| Referral | Clickstream-specific |
| Part, Vendor, Status, Carrier | Supply chain |
| Facilities Location | Supply chain |
| Media, Promotion | Marketing |
| Internal Organization, Employee | Operations |

### 1.3 Page Dimension

Describes the page context for a web page event. Grain = individual page.

| Attribute | Sample Values |
|-----------|---------------|
| Page Key | Surrogate values (1..N) |
| Page Source | Static, Dynamic, Unknown, Corrupted, Inapplicable |
| Page Function | Portal, Search, Product description, Corporate information |
| Page Template | Sparse, Dense |
| Item Type | Product SKU, Book ISBN number, Telco rate type |
| Graphics Type | GIF, JPG, Progressive disclosure, Size pre-declared |
| Animation Type | Similar to graphics type |
| Sound Type | Similar to graphics type |
| Page File Name | Optional application-dependent name |

Design notes:
- Static pages get their own row; dynamic pages grouped by similar function and type
- When a static page definition changes, the row can be overwritten (Type 1) or kept for historical analysis (Type 2)
- Need extra sub-dimensions for graphical elements, links, or more granular page components

### 1.4 Event Dimension

Describes what happened on a particular page at a particular point in time.

| Attribute | Sample Values |
|-----------|---------------|
| Event Key | Surrogate values (1..N) |
| Event Type | Open page, Refresh page, Click link, Unknown, Inapplicable |
| Event Content | Application-dependent fields eventually driven by XML tags |

### 1.5 Session Dimension

Provides one or more levels of diagnosis for the visitor's session as a whole.

| Attribute | Sample Values |
|-----------|---------------|
| Session Key | Surrogate values (1..N) |
| Session Type | Classified, Unclassified, Corrupted, Inapplicable |
| Local Context | Page-derived context like "Requesting Product Information" |
| Session Context | Trajectory-derived context like "Ordering a Product" |
| Action Sequence | Summary label for overall sequence of actions during session |
| Success Status | Whether overall session mission was accomplished |
| Customer Status | New customer, High value customer, About to cancel, In default |

Analytical questions enabled:
- How many customers consulted product information before ordering?
- How many looked at product information and never ordered?
- How many did not finish ordering? Where did they stop?

### 1.6 Referral Dimension

Describes how the customer arrived at the current page.

| Attribute | Sample Values |
|-----------|---------------|
| Referral Key | Surrogate values (1..N) |
| Referral Type | Intra site, Remote site, Search engine, Corrupted, Inapplicable |
| Referring URL | www.organization-site.com/linkspage |
| Referring Site | www.organization-site.com |
| Referring Domain | www.organization-site.com |
| Search Type | Simple text match, Complex logical match |
| Specification | Actual spec used (useful if simple text, otherwise questionable) |
| Target | Meta tags, Body text, Title (where search found its match) |

### 1.7 Clickstream Session Fact Table (Figure 15-5)

**Grain:** One row per completed customer session.

**ROLE-PLAYING DIMENSION EXAMPLE:** The Date dimension appears twice as two different foreign keys -- Universal Date Key and Local Date Key. This is a classic role-playing dimension pattern where the same physical dimension table is aliased/viewed as two logical roles.

```
Clickstream Session Fact
========================
Universal Date Key (FK)     --> Date Dimension (2 views for roles)
Universal Date/Time
Local Date Key (FK)         --> Date Dimension (2 views for roles)
Local Date/Time
Customer Key (FK)           --> Customer Dimension
Entry Page Key (FK)         --> Entry Page Dimension
Session Key (FK)            --> Session Dimension
Referrer Key (FK)           --> Referrer Dimension
Session ID (DD)
------- Facts -------
Session Seconds
Pages Visited
Orders Placed
Order Quantity
Order Dollar Amount
```

**Key design decisions:**
- **Role-playing dimension:** Date Dimension used for both Universal Date and Local Date (2 views of same dim)
- **Degenerate dimension:** Session ID stored directly in fact table as DD (not FK to separate dim)
- **Grain choice:** Session level (not page event level) -- this is the coarser of two clickstream grains

---

## 2. Kimball Model Sharing -- Electronic Commerce Part 2

**Source:** `E:\Shopee\Shopee 2022\Confluence Save\Kimball Model Sharing - Electronic Commerce part2(1).pptx`
**Slides:** 10 | **Topic:** Page event fact table, step dimension, aggregation, bus matrix, profitability

### 2.1 Clickstream Page Event Fact Table

**Grain:** Individual page event within each customer session (finer than Session Fact).

This fact table can become astronomical in size. Resist the urge to aggregate -- that involves dropping dimensions.

```
Clickstream Page Event Fact
===========================
Universal Date Key (FK)           --> Date Dimension (2 views for roles)
Universal Date/Time
Local Date Key (FK)               --> Date Dimension (2 views for roles)
Local Date/Time
Customer Key (FK)                 --> Customer Dimension
Page Key (FK)                     --> Page Dimension
Event Key (FK)                    --> Event Dimension
Session Key (FK)                  --> Session Dimension
Session ID (DD)
Session Step Key (FK)             --> Step Dimension (3 views for roles)
Purchase Step Key (FK)            --> Step Dimension (3 views for roles)
Abandonment Step Key (FK)         --> Step Dimension (3 views for roles)
Product Key (FK)                  --> Product Dimension
Referrer Key (FK)                 --> Referrer Dimension
Promotion Key (FK)                --> Promotion Dimension
------- Facts -------
Page Seconds
Order Quantity
Order Dollar Amount
```

**ROLE-PLAYING DIMENSIONS (two examples in one fact table):**

1. **Date Dimension (2 roles):** Universal Date Key + Local Date Key -- same date dim, different timezone perspectives
2. **Step Dimension (3 roles):** Session Step Key + Purchase Step Key + Abandonment Step Key -- same step dimension used for three different analytical perspectives on position within a session

### 2.2 Step Dimension (Role-Playing, 3 Roles)

The step dimension provides the position of the specific page event within the overall session. It is used in 3 roles simultaneously:

| Attribute | Description |
|-----------|-------------|
| Step Key (PK) | Surrogate key |
| Total Number Steps | Total steps in the session |
| This Step Number | Position of current event |
| Steps Until End | Remaining steps |

**Sample rows:**

| Step Key | Total Number Steps | This Step Number | Steps Until End |
|----------|--------------------|------------------|-----------------|
| 1 | 1 | 1 | 0 |
| 2 | 2 | 1 | 1 |
| 3 | 2 | 2 | 0 |
| 4 | 3 | 1 | 2 |
| 5 | 3 | 2 | 1 |
| 6 | 3 | 3 | 0 |

The three FK roles in the fact table allow analysis like:
- **Session Step:** Where in the overall browsing session is this event?
- **Purchase Step:** Where in the purchase funnel is this event?
- **Abandonment Step:** How close to abandonment is this event?

### 2.3 Aggregate Clickstream Fact Table

Both clickstream fact tables are large. An aggregate fact table reduces size to less than 1% of the original, yielding 100x query performance improvement.

**Grain:** Grouped by month, demographic type, entry page, and session outcome.

```
Session Aggregate Fact
======================
Universal Month Key (FK)        --> Month Dimension
Demographic Key (FK)            --> Demographic Dimension
Entry Page Key (FK)             --> Entry Page Dimension
Session Outcome Key (FK)        --> Session Outcome Dimension
------- Facts -------
Number of Sessions
Session Seconds
Pages Visited
Orders Placed
Order Quantity
Order Dollar Amount
```

**Design decision:** Count of sessions + sum of all additive facts from the session-grained fact table. The dimension reduction (from date to month, from customer to demographic type) is what makes the aggregate tiny.

### 2.4 Bus Matrix -- Integrating Clickstream into Web Retailer

The bus matrix shows how clickstream integrates with existing business processes via conformed dimensions:

| Business Process | Date | Part | Vendor | Carrier | Facility | Product | Customer | Media | Promotion | Service Policy | Internal Org | Employee | Clickstream (4 dims) |
|-----------------|------|------|--------|---------|----------|---------|----------|-------|-----------|---------------|-------------|----------|---------------------|
| **Supply Chain** | | | | | | | | | | | | | |
| Supplier Purchase Orders | X | X | X | | | | | | | | X | | |
| Supplier Deliveries | X | | X | X | X | | | | | | | | |
| Part Inventories | X | X | X | | X | | | | | | | | |
| Assembly Bill of Materials | X | X | X | | X | X | | | | | | | |
| Assembly to Order | X | X | X | X | X | X | | | | | | | |
| **Customer Relationship** | | | | | | | | | | | | | |
| Product Promotions | X | | | | | X | X | X | X | | | X | |
| Advertising | X | | | | | | | X | | | | | X |
| Customer Communications | X | | | | | | X | | | | | X | |
| Customer Inquiries | X | | X | | | X | X | | | X | | | |
| **Web Visitor Clickstream** | **X** | | | | | **X** | **X** | **X** | **X** | | | | **X** |
| Product Orders | X | | | | | X | X | | | | | | |
| Service Policy Orders | X | | X | | X | X | X | | | X | | | |
| Product Shipments | X | | | X | X | X | X | | | | | | |

**Key insight:** The Web Visitor Clickstream row shares conformed dimensions (Date, Product, Customer, Media, Promotion) with other business processes. The "Clickstream (4 dims)" column represents the 4 clickstream-specific dimensions: Page, Event, Session, Referral.

### 2.5 Profitability Fact Table (Cross-Channel Including Web)

Extension of the sales transaction process to full profit-and-loss analysis.

**Grain:** Each individual line item sold on a sales ticket to a customer at a point in time.

```
Profitability Fact
==================
Universal Date Key (FK)             --> Date Dimension (2 views for roles)
Universal Time of Day Key (FK)      --> Time of Day Dimension (2 views for roles)
Local Date Key (FK)                 --> Date Dimension (2 views for roles)
Local Time of Day Key (FK)          --> Time of Day Dimension (2 views for roles)
Customer Key (FK)                   --> Customer Dimension
Channel Key (FK)                    --> Channel Dimension
Product Key (FK)                    --> Product Dimension
Promotion Key (FK)                  --> Promotion Dimension
Ticket Number (DD)
------- Facts -------
Units Sold
Gross Revenue
Manufacturing Allowance
Marketing Promotion
Sales Markdown
Net Revenue
Manufacturing Cost
Storage Cost
Gross Profit
Freight Cost
Special Deal Cost
Other Overhead Cost
Net Profit
```

**ROLE-PLAYING DIMENSIONS (doubled):**
- Date Dimension serves 2 roles (Universal Date, Local Date)
- Time of Day Dimension serves 2 roles (Universal Time, Local Time)

Analytical questions:
- How profitable is each channel (web sales, telesales, store sales)? Why?
- When is your business most profitable? Why?
- Who are the profitable customers in each channel? Why?
- Which promotions work on the web but not in other channels? Why?

---

## 3. Order Mart 3.0 Introduction (Shopee Production)

**Source:** `E:\Shopee\Shopee Slide Archive\Order Mart 3.0 Intro.pptx`
**Slides:** 82 | **Topic:** Shopee's production order mart dimensional model -- architecture, entities, metrics, promotions, vouchers, prorate logic

### 3.1 Architecture Layers

| Layer | Name | Description | Usage |
|-------|------|-------------|-------|
| ADS | Application Data Store | Cross-domain metrics for applications and reports | Reports, data products, campaign station, seller center |
| DWS | Data Warehouse Summary | Aggregated DWD tables by dimension and time granularity | Profiling needs (user/item profile), basic reporting |
| DWD + DIM | Data Warehouse Detail + Dimension | Denormalized fact tables (multidimensional model) + descriptive dimension tables | Ad-hoc analysis to identify root cause of business issues; most granular data |
| ODS | Operation Data Store | Raw data for mart development (internal only) | N/A (not exposed to users) |

### 3.2 Order Flow -- 5 Key Stages

1. **Checkout** (Order Placement)
2. **Order Payment**
3. **Order Fulfilment** (covered by separate fulfilment mart)
4. **Return and Refund** (After Sales)
5. **Escrow**

COD (Cash on Delivery) orders have different flow: payment is AFTER fulfilment.

### 3.3 Key Entities and Grain Decisions

**Entity hierarchy:**

```
Checkout (1)
  |
  +-- Order 1 (1 buyer + 1 shop per checkout)
  |     +-- Order Item 1 (MPSKU level)
  |     +-- Order Item 2
  |     +-- Order Item 3 (bundle)
  |           +-- Bundle Item 1
  |           +-- Bundle Item 2
  |
  +-- Order 2
  |     +-- Order Item 1
  |     ...
  ...
```

**Grain decisions:**
- **Order level:** One row per order (contract between 1 buyer and 1 shop in 1 checkout)
- **Order item level:** One row per MPSKU (lowest granular unit -- the specific model/SKU the buyer purchased)
- **Return request level:** One row per return order item (subset of order items selected for return)

**Primary key for order_item table:** `(order_id, item_id, model_id, bundle_order_item_id, group_id)`

### 3.4 DI vs DF Table Pattern (CRITICAL -- Accumulating Snapshot vs Transaction)

**This is Shopee's implementation of two complementary fact table types:**

#### DI Tables (Transaction Fact / Event Snapshot)

`xx_di` tables record **multiple events** in an order lifecycle. A single order appears up to 3 times (placed, paid, completed).

| order_id | Metrics | is_placed | is_paid | is_completed | grass_date |
|----------|---------|-----------|---------|--------------|------------|
| 12345 | ... | 1 | 0 | 0 | 2020-10-22 |
| 12345 | ... | 0 | 1 | 0 | 2020-10-23 |
| 12345 | ... | 0 | 0 | 1 | 2020-10-30 |

Rules:
1. MUST filter with `is_placed`, `is_paid`, `is_completed` flags -- otherwise double-counting
2. `grass_date` = event date (NOT order create date)
3. GMV may change after placement when user changes payment method (<0.1% of cases)

#### DF Tables (Accumulating Snapshot / Profile)

`xx_df` tables provide the **latest information** of all orders. Each order appears exactly once. Updated until terminal status (invalid, escrow_paid, cancel_complete).

| order_id | Metrics | grass_date |
|----------|---------|------------|
| 12345 | ... | 2020-11-02 (terminal date) |

Rules:
1. `grass_date` = date when order reached terminal status
2. Non-terminated orders stored in `9999-01-01` partition
3. Once terminal, no further updates (with rare exceptions for certain fields)

**This maps directly to Kimball's accumulating snapshot pattern:** the DF table is an accumulating snapshot fact where the row evolves through milestones (placed -> paid -> shipped -> completed -> escrow) until reaching a terminal state.

### 3.5 DWD Table Catalog

| Table | Grain | Type |
|-------|-------|------|
| `order_mart_dwd_order_place_pay_complete_di` | Order-level transaction snapshots at place/pay/complete events | DI (event) |
| `order_mart_dwd_order_item_place_pay_complete_di` | Order-item-level transaction snapshots at place/pay/complete events | DI (event) |
| `order_mart_dwd_order_all_event_final_status_df` | All order transaction details, updated until terminal status | DF (profile) |
| `order_mart_dwd_order_item_all_event_final_status_df` | All order-item details, updated until terminal status (PK: order_id, item_id, model_id, bundle_order_item_id, group_id) | DF (profile) |

### 3.6 DWS Aggregate Tables

| Table Pattern | Grain |
|---------------|-------|
| `order_mart_dws_item_gmv_{1d,nd,mtd,td}` | Item (item_id) aggregated daily |
| `order_mart_dws_sku_gmv_{1d,nd,mtd,td}` | SKU (item_id + model_id) aggregated daily |
| `order_mart_dws_seller_gmv_{1d,nd,mtd,td}` | Shop (shop_id) aggregated daily |
| `order_mart_dws_buyer_gmv_{1d,nd,mtd,td}` | Buyer (buyer_id) aggregated daily |

Suffixes: `1d` = daily, `nd` = N-day rolling, `mtd` = month-to-date, `td` = to-date (lifetime).

### 3.7 Star Schema -- Order/Order Item Fact Dimensions

Central fact table: **Order / Order Item** with measures:
- Buyer and seller costs
- Rebates and voucher metrics
- Coin metrics
- Logistics cost metrics
- Order time and status

**Surrounding dimensions:**

| Dimension | Side |
|-----------|------|
| Voucher Dimension | Left |
| Payment Channel Dimension | Left |
| Logistic Channel Dimension | Left |
| Return Order Dimension | Left |
| Fees (Commission/Service) Dimensions | Left |
| Date Dimension | Right |
| Checkout Dimension | Right |
| Item Dimension | Right |
| Seller / Shop Dimension | Right |
| User (Buyer) Dimension | Right |

### 3.8 Order State Machine

**16 order states** (corresponding to `order_be_status`):

| ID | Status | Terminal? | Description |
|----|--------|-----------|-------------|
| 0 | delete | | Initial state during order creation |
| 1 | unpaid | | Before payment (COD stays here until delivery+payment) |
| 2 | paid | | After payment done |
| 3 | shipped | | No longer in use |
| 4 | completed | | Buyer clicked "received" or timeout; next = escrow |
| 6 | invalid | Yes | COD: not delivered; Non-COD: cancelled before payment |
| 7 | cancel processing | | Cancel initiated after payment, before delivery |
| 8 | cancel completed | Yes | Refund process completed |
| 9 | return processing | | Return request initiated after delivery |
| 10 | return completed | | Return done; check if escrow needed |
| 11 | escrow paid | Yes | Final state -- seller paid out |
| 12 | escrow created | | First escrow status after completion/return |
| 13 | escrow pending | | Escrow blocked (fraud/risk), manual intervention needed |
| 14 | escrow verified | | Escrow verified, ready for payout |
| 15 | escrow payout | | Payment being transferred to seller |
| 16 | cancel pending | | Rare: buyer cancel needs seller approval |

Terminal states = end of lifecycle, no further updates. "Completed" is NOT terminal -- escrow still follows.

### 3.9 Timezone Handling

| Column Pattern | Data Type | Timezone |
|----------------|-----------|----------|
| `grass_date` | date | DWD/DIM = local timezone; DWS = depends on `tz_type` (local or SGT) |
| `xx_timestamp` | integer | Unix time in UTC. Convert: `from_unixtime(create_timestamp, 'Asia/Jakarta')` |
| `xx_datetime` | string | Local timezone in DWD; `tz_type` timezone in DWS |

**CRITICAL:** DWS tables may contain metrics in both timezones. Always include `tz_type` in filter to avoid double-counting.

### 3.10 GMV Formula (Checkout Metrics)

```
gmv = buyer_paid_shipping_fee
    + merchandise_subtotal_amt
    + buyer_txn_fee
    - tax_exemption_amt
    - promotion_fees
```

Where:
- `buyer_paid_shipping_fee = estimate_shipping_fee - shipping_discount`
- `merchandise_subtotal_amt = SUM(order_price_pp * item_amount)` for all order items
- `promotion_fees` includes: platform voucher rebates (shopee + seller absorbed), seller voucher rebates, coin used, card/payment rebates

### 3.11 Item Pricing Hierarchy

```
item_price_before_discount_pp = $25.90  (original price)
item_price_pp = $9.90                   (display price after item promotions)
order_price_pp = $9.90                  (price buyer pays; differs from item_price when bundle/offer deal)
item_input_price_pp = item_price_pp - item_tax  (seller's input price, relevant for ID/Indonesia tax)
```

Cases where `order_price_pp != item_price_pp`: Bundle deals, Seller Offer deals.

### 3.12 Item Promotion Taxonomy

| Promotion Type | Identification Logic | FK |
|---------------|---------------------|-----|
| Product promotions | `item_promotion_source = 'shopee'` | item_promotion_id |
| Seller discount | `item_promotion_source = 'seller'` | item_promotion_id |
| Selling price | `item_promotion_source = 'selling_price'` | item_promotion_id |
| Flash sale (normal) | `item_promotion_source = 'flash_sale' AND flash_sale_type = 'FLASH_SALE_NORMAL'` | item_promotion_id |
| Brand flash sale | `item_promotion_source = 'flash_sale' AND flash_sale_type = 'FLASH_SALE_BRAND'` | item_promotion_id |
| Shop flash sale | `item_promotion_source = 'flash_sale' AND flash_sale_type = 'FLASH_SALE_SELLER'` | item_promotion_id |
| Group buy | `is_group_buy_deal = 1` | group_buy_deal_id |
| Exclusive price | `is_exclusive_price_deal = 1` | exclusive_price_group_id + item_promotion_id |
| Bundle deal | `is_bundle_deal = 1` | bundle_deal_id |
| Add-on deal | `is_add_on_deal = 1 AND add_on_deal_type = 'ADD_ON_DEAL'` | add_on_deal_id |
| Purchase with gift | `is_add_on_deal = 1 AND add_on_deal_type = 'PURCHASE_WITH_GIFT'` | add_on_deal_id |
| Purchase with purchase | `is_add_on_deal = 1 AND add_on_deal_type = 'PURCHASE_WITH_PURCHASE'` | add_on_deal_id |
| Offer deal (chat) | `is_offer_item = 1` | item_offer_id |

Package promotion types:
- **Bundle deal:** Buy X min qty of main items to get Y% or $Y off total
- **Add-on deal:** Buy any 1 main item to get Y% or $Y off sub items
- **Purchase with gift:** Buy $X min of main items to get free sub items
- **Purchase with purchase:** Buy $X min or X qty of main items to get Y% or $Y off sub items

### 3.13 Voucher System

Vouchers are entitlements to promotions used by buyers to offset costs, gain coin cashbacks, or unlock logistics/payment promotions.

**Selection allowance per checkout:** 1 or 2 platform vouchers + 1 shop voucher per shop ("1+N" or "2+N"). For 2+N: only 1 FSV + 1 Discount/Coin.

| Platform/Shop | Voucher Type | Borne By | Key Columns |
|--------------|-------------|----------|-------------|
| Platform | FSV (Free Shipping) | Shopee | fsv_promotion_id, fsv_voucher_code, logistics_channel_*_rule_id |
| Platform | Discount | Shopee | pv_voucher_code, pv_promotion_id, is_pv_seller_absorbed = 0 |
| Platform | Discount | Seller | pv_voucher_code, pv_promotion_id, is_pv_seller_absorbed = 1 |
| Platform | Coin Cashback | Shopee | pv_voucher_code, pv_promotion_id, is_pv_seller_absorbed = 0 |
| Platform | Coin Cashback | Seller | pv_voucher_code, pv_promotion_id, is_pv_seller_absorbed = 1 |
| Shop | Discount | Shopee | sv_voucher_code, sv_promotion_id, is_sv_seller_absorbed = 0 |
| Shop | Discount | Seller | sv_voucher_code, sv_promotion_id, is_sv_seller_absorbed = 1 |
| Shop | Coin Cashback | Shopee | sv_voucher_code, sv_promotion_id, is_sv_seller_absorbed = 0 |
| Shop | Coin Cashback | Seller | sv_voucher_code, sv_promotion_id, is_sv_seller_absorbed = 1 |

**Order vs. Order Item granularity difference:** Voucher keys and rebate amounts are stored at order level when applied, but at order item level ONLY if the voucher rule is applicable to that specific item. Items not covered by the voucher have NULL voucher fields.

### 3.14 Escrow Calculation

```
escrow_to_seller_amt = gmv
    - pv_rebate_by_shopee_amt
    - sv_rebate_by_shopee_amt
    - coin_used_cash_amt
    - card_rebate_by_shopee_amt
    - card_rebate_by_bank_amt
    - SUM(item_rebate_by_shopee_amt) for all order items
    - actual_shipping_rebate_by_shopee_amt
    - actual_shipping_fee (cashless channel only)
    - pv_coin_earn_by_seller_amt
    - sv_coin_earn_by_seller_amt
    - seller_txn_fee
    - buyer_txn_fee
    - commission_fee
    - service_fee
    - item_tax_amt (cashless channel only)
    - shipping_discount_by_3pl_to_seller_amt (ID orders only)
```

### 3.15 Order Fraction Logic (Prorate for Aggregation)

When aggregating from order_item level using item-level dimensions (e.g., category), use `order_fraction` to avoid double-counting orders.

```
order_fraction = 1/count(distinct itemid)
    * 1/count(distinct modelid | itemid)
    * 1/count(distinct bundle_order_itemid | (itemid, modelid))
    * 1/count(distinct groupid | (itemid, modelid, bundle_order_itemid))
```

Example for an order with Normal SKU A (111), Normal SKU B (222), and a Bundle Deal containing SKU B (222) + SKU C (222/333):

| ID | itemid | Item weight | modelid | Model weight | bundle_itemid | Bundle weight | groupid | Group weight | order_fraction |
|----|--------|-------------|---------|--------------|---------------|---------------|---------|--------------|----------------|
| Normal SKU A | 111 | 0.5 | 111 | 1 | 0 | 1 | 0 | 1 | **0.5** |
| Normal SKU B | 222 | 0.5 | 222 | 0.5 | 0 | 0.5 | 0 | 1 | **0.125** |
| Bundle SKU B | 222 | 0.5 | 222 | 0.5 | 1 | 0.5 | 0 | 1 | **0.125** |
| Bundle SKU C | 222 | 0.5 | 333 | 0.5 | 1 | 1 | 0 | 1 | **0.25** |
| **Total** | | | | | | | | | **1.0** |

### 3.16 Split Factor Logic (Metric Proration)

When metrics are not available at the lowest granularity, split factors prorate them from higher to lower granularity:

**Order -> Order Item:**
```
split_factor = (amt * order_price) / SUM(amt * order_price)  -- for all items in order
-- If SUM = 0, use order_fraction instead
```

**Bundle Deal -> Individual Items:**
```
bundle_split_factor = (amt * item_price) / SUM(amt * item_price)  -- for items in bundle
-- If SUM = 0, use bundle_order_fraction instead
bundle_order_fraction = 1/count(distinct itemid) * 1/count(distinct modelid | itemid)
```

### 3.17 Net Order Classification

`is_net_order` column classifies orders for net metric calculations.

**Pre-2021 logic:** Non-net if cancelled/invalid OR returned successfully (status 2 or 5).

**Post-2021 logic (current):** Non-net if:
1. Cancelled or invalid (`be_status IN ('Cancel_Completed', 'Invalid')`) -- no change
2. Returned AND it is a **full return** (refund amount = GMV, or NMV = 0)

The change recognizes that partial returns still generate revenue (commission/service fees) and platform costs (rebates), so partial-return orders remain "net."

### 3.18 Key Column Definitions

| Column | Description |
|--------|-------------|
| `is_net_order` | Order not cancelled/invalid AND not fully returned |
| `is_bi_exclude` | Excludes shops that should not count in overall GMV (paid ads, promotional games, etc.) |
| `is_cod_order` | COD (Cash on Delivery) order identifier |
| `fulfilment_source` | Identifies orders shipped from Shopee warehouse (distinct from `is_sbs` which has local business meaning) |
| `payment_be_channel` | Backend payment channel (denormalized -- no need to join checkout_tab) |

---

## 4. Cross-Cutting Patterns for GME Mart Reference

### 4.1 Role-Playing Dimensions Catalog

| Dimension | Roles | Source |
|-----------|-------|--------|
| Date Dimension | Universal Date Key, Local Date Key | Part 1 Session Fact, Part 2 Page Event Fact, Part 2 Profitability Fact |
| Time of Day Dimension | Universal Time of Day Key, Local Time of Day Key | Part 2 Profitability Fact |
| Step Dimension | Session Step Key, Purchase Step Key, Abandonment Step Key | Part 2 Page Event Fact |
| Page Dimension | Entry Page Key (in Session Fact), Page Key (in Page Event Fact) | Part 1 + Part 2 |

### 4.2 Fact Table Grain Spectrum

| Fact Table | Grain | Relative Size |
|------------|-------|---------------|
| Clickstream Page Event Fact | Individual page event per session | Largest |
| Clickstream Session Fact | Complete customer session | Large |
| Session Aggregate Fact | Monthly by demographic/entry page/outcome | <1% of session fact |
| Profitability Fact | Individual line item per sales ticket | Medium |
| Order Mart DI | Order-level per event (placed/paid/completed) | 3x order count |
| Order Mart DF | Order-level profile (one row per order) | 1x order count |
| DWS Aggregates | Daily by item/SKU/seller/buyer | Smallest |

### 4.3 Accumulating Snapshot Pattern (DI/DF)

Shopee's DI/DF pattern maps directly to Kimball's accumulating snapshot:

- **DI tables** = transaction fact tables recording each event milestone as a separate row (closer to a transaction grain, but with event-type flags)
- **DF tables** = accumulating snapshot fact tables where one row per order is updated through its lifecycle until reaching a terminal state
- The `grass_date = '9999-01-01'` partition for non-terminated orders is a production-ready implementation of the "incomplete snapshot" pattern
- Terminal states (invalid, escrow_paid, cancel_complete) freeze the row permanently

### 4.4 Bus Matrix Integration Points

The clickstream bus matrix shows that Date, Product, Customer, Media, and Promotion are **conformed dimensions** shared across supply chain, CRM, and clickstream business processes. This is the foundation for cross-process analysis.

For GME Mart: the equivalent conformed dimensions would be:
- **Date** -- shared across order facts, market data, and option pricing
- **Security/Instrument** -- shared across positions, trades, and market data
- **Account** -- shared across positions and cash flows

### 4.5 Denormalization Decisions in Order Mart 3.0

Order Mart 3.0 achieved 60% average improvement in query performance by:
1. Denormalizing highly-used dimensions directly into fact tables (no joins needed)
2. Partitioning data by event datetime (reducing full-table scans)
3. Removing the 64-day update limitation from v2.0
4. Consistent naming conventions across metrics
5. Storing datetime as strings to avoid timezone auto-conversion issues in Presto

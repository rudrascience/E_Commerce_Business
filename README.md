# 07 · E-commerce Business Analysis

**Module:** SQL  **Dataset:** [Olist Brazilian E-commerce](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce): ~100k real, anonymised orders, Sep 2016 – Oct 2018 (CC BY-NC-SA 4.0). Project 05 uses the same data.  **Column profile:** [DATA_PROFILE.md](DATA_PROFILE.md)

---

## 1. Project description

**Business context.** Olist connects small Brazilian sellers to large marketplaces. The analytics team must answer leadership's questions directly from the transactional database: growth, customer retention, payment behaviour, logistics performance and seller quality. The outputs are written as SQL views and reports.

**Objective.** Design and load a 9-table relational schema, validate it, and answer ~25 business questions with SQL (multi-table joins, CTEs, window functions, cohorts and RFM). Package reusable logic as views and functions.

**Stakeholders.** Leadership, marketing (retention), operations (logistics), the seller-relations team.

**Key questions**
1. How fast is the business growing (revenue, orders, AOV, MoM)?
2. Which categories, states and sellers drive revenue?
3. How many customers return? How do cohorts retain?
4. How do customers pay (type, installments)?
5. How good is delivery, and how does it affect review scores?

## 2. Dataset & schema

```
customers (customer_id PK, customer_unique_id, zip, city, state)
   │1
   │n
orders (order_id PK, customer_id FK, order_status, purchase_ts, approved_at,
   │    delivered_carrier_date, delivered_customer_date, estimated_delivery_date)
   ├──< order_items   (order_id, order_item_id, product_id FK, seller_id FK, shipping_limit_date, price, freight_value)
   ├──< order_payments(order_id, payment_sequential, payment_type, payment_installments, payment_value)
   └──< order_reviews (review_id, order_id, review_score, comment_title, comment_message, created, answered)
products (product_id PK, product_category_name, …dimensions) ── category_translation (pt → en)
sellers  (seller_id PK, zip, city, state)
geolocation (zip_prefix, lat, lng, city, state)  -- NOT unique per zip
```

| Table | Rows |
|---|---|
| orders | 99,441 |
| order_items | 112,650 |
| order_payments | 103,886 |
| order_reviews | 99,225 |
| customers | 99,441 (96,096 unique people) |
| products | 32,951 |
| sellers | 3,095 |
| geolocation (`.csv.gz`) | 1,000,163 |

---

## 3. Data cleaning (SQL)

| # | Issue found | SQL fix |
|---|---|---|
| 1 | Timestamps arrive as text | Create columns as `TIMESTAMP`; `\copy` parses ISO text directly |
| 2 | Geolocation is gzipped | `\copy geolocation FROM PROGRAM 'gunzip -c olist_geolocation_dataset.csv.gz' CSV HEADER` |
| 3 | `customer_id` is per order, not per person | Always use `customer_unique_id` for customer counts and retention |
| 4 | 610 products have no category | `COALESCE(t.product_category_name_english, 'unknown')` |
| 5 | Category names in Portuguese | `LEFT JOIN category_translation` |
| 6 | Misspelt columns `product_name_lenght`, `product_description_lenght` | `ALTER TABLE products RENAME COLUMN …` |
| 7 | Undelivered orders have NULL delivery dates (3%) | Filter `order_status = 'delivered' AND order_delivered_customer_date IS NOT NULL` for delivery metrics |
| 8 | Multiple reviews per order (some `review_id`s repeat) | `DISTINCT ON (order_id) … ORDER BY review_answer_timestamp DESC` |
| 9 | Fan-out: items × payments multiplies rows | Aggregate each child table to order level in a **CTE** before joining |
| 10 | Geolocation has 261,831 duplicate rows | `CREATE TABLE geo_zip AS SELECT zip, AVG(lat), AVG(lng) … GROUP BY zip` |
| 11 | Reviews free text | Mostly empty (88% no title); keep it, but exclude it from the numeric analysis |

Add primary keys, foreign keys and indexes on `order_items(order_id)`, `order_items(product_id)`, `order_items(seller_id)` and `orders(customer_id)`.

---

## 4. Analysis (EDA with SQL)

**Sales**
1. Monthly revenue, orders, AOV; MoM growth with `LAG()`
2. Top 10 categories by revenue and by units
3. Revenue by customer state; seller-state → customer-state flow matrix
4. Black Friday vs normal-week revenue

**Customers**
5. New vs returning customers per month (first order via `MIN(purchase_ts) OVER (PARTITION BY customer_unique_id)`)
6. Repeat-purchase rate
7. **Cohort retention matrix:** first-order month × months since
8. **RFM** with `NTILE(5)`; segment sizes and revenue

**Payments**
9. Share by payment type; average installments by price band; orders paid with 2+ methods

**Delivery & satisfaction**
10. Average and median delivery days by state (`PERCENTILE_CONT(0.5)`)
11. Late % by state and month
12. Average review for late vs on-time; % of 1–2 star reviews

**Sellers**
13. Top sellers (`DENSE_RANK`); revenue share of the top 10% of sellers
14. Sellers with average review < 3 and > 50 orders (risk list)

**Reusable objects**
- `VIEW order_summary`: one row per order with revenue, freight, payment, review, delivery days and late flag
- `FUNCTION seller_scorecard(seller_id)`: orders, revenue, average review, late %

---

## 5. Testing

**A. Data-integrity tests** (each query should return 0 rows or the expected number)

| Test | Expected |
|---|---|
| Orders with no items | 775 (canceled / unavailable). Explain them |
| Items whose `order_id` isn't in orders (FK) | 0 |
| `SUM(payment_value)` vs `SUM(price + freight)` per order: differences > R$1 | **249 of 98,665 orders** (installment interest, vouchers). Investigate the top 10 |
| Distinct `customer_unique_id` | 96,096 |
| `order_summary` view row count = orders | 99,441 |
| Revenue from the view = revenue from the raw items | 13.59 M |

**B. Statistical tests** (on query outputs)

| Hypothesis | Result |
|---|---|
| H₀: review score is the same for late and on-time orders | 2.27 vs 4.29, p ≈ 0. **Reject H₀** |
| H₀: freight share is unrelated to review score | Spearman ρ = −0.03 (p < 0.001). Significant but negligible |
| H₀: delivery days are equal across states | ANOVA. SP 8 days vs RR 29 days. **Reject H₀** |

---

## 6. Observations (from this data)

1. **Revenue R$13.59 M** (+R$2.25 M freight), 99,441 orders, **AOV R$138** (median R$87).
2. **Growth:** monthly orders rose from 800 (Jan 2017) to ~7,000 (2018); Jan–Aug revenue **2.4× year on year**. Peak month: **Nov 2017 (Black Friday), 7,544 orders**.
3. **Categories:** health & beauty, watches & gifts and bed-bath-table lead (R$1.0–1.3 M each).
4. **Geography:** SP **38%** of revenue; SP + RJ + MG = 63%.
5. **Retention is the big weakness:** only **3.1%** of the 96,096 unique customers placed a second order.
6. **Payments:** credit card 74% (avg **3.5 installments**), boleto 19%, voucher 5.6%, debit 1.5%.
7. **Logistics:** average 12.1 days to deliver, **6.8% late**; SP 8.3 days vs the northern states 26–29 days.
8. **Satisfaction:** average review 4.09; 58% are 5-star, but **11.5% are 1-star**. Late orders average **2.27** stars and 62% of them get 1–2 stars.
9. **Sellers:** the top 10% of sellers make **67.5%** of revenue. Cancellation + unavailable = 1.2% of orders.

## 7. Recommendations

1. **Retention programme:** with 97% one-time buyers, launch win-back emails at 30/60 days, loyalty credit and personalised recommendations from category history.
2. **Logistics SLAs:** a seller dispatch SLA, carrier scorecards and realistic regional delivery estimates. The 6.8% late orders produce most of the 1-star reviews.
3. **Regional fulfilment:** warehouses or partner carriers for the North and North-East to cut 26–29-day deliveries.
4. **Seller-quality gate:** auto-flag sellers with an average review < 3 and > 50 orders for coaching or suspension.
5. **Seasonal readiness:** scale capacity for November (Black Friday is ~1.5× a normal month).
6. **Payments:** offer interest-free installments on high-ticket categories to lift AOV.

## 8. Deliverables

`01_schema.sql`, `02_load_clean.sql`, `03_tests.sql`, `04_analysis.sql`, `05_views_functions.sql`, and a README with results and insights.

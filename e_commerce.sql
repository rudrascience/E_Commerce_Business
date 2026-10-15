CREATE DATABASE E_Commerce;
use E_Commerce;

-- Renaming the tables.
RENAME TABLE olist_customers_dataset TO CUSTOMERS;
RENAME TABLE olist_order_items_dataset TO ITEMS;
RENAME TABLE olist_order_payments_dataset TO PAYMENTS;
RENAME TABLE olist_order_reviews_dataset TO REVIEWS;
RENAME TABLE olist_orders_dataset TO ORDERS;
RENAME TABLE olist_products_dataset TO PRODUCTS;
RENAME TABLE olist_sellers_dataset TO SELLERS;
RENAME TABLE product_category_name_translation TO CATEGORY;

-- View Tables.

SELECT * FROM orders
LIMIT 5;

SELECT * FROM customers
LIMIT 5;

SELECT * FROM items
LIMIT 5

-- Q.1> Find orders_per_day.

SELECT
    DATE(order_purchase_timestamp) AS day,
    COUNT(*) AS order_count
FROM orders
GROUP BY day
LIMIT 10;

-- Q.2> Find orders_per_day_of_the_week_and_hour.

SELECT
DAYNAME(order_purchase_timestamp)AS day_number,
DAYNAME(order_purchase_timestamp) AS day_of_week,
HOUR(order_purchase_timestamp)AS order_hour,
COUNT(order_id) AS total_orders
FROM orders
GROUP BY
DAYOFWEEK(order_purchase_timestamp),
DAYNAME(order_purchase_timestamp),
HOUR(order_purchase_timestamp)
ORDER BY
day_number, order_hour;

-- Q.3> What is the orders_per_city_reversed.
SELECT
c.customer_city,
COUNT(o.order_id)AS total_orders
FROM orders o
JOIN customers c ON o.customer_id=c.customer_id
GROUP BY c.customer_city
ORDER BY total_orders DESC

-- Q.4> What is the monthly Revenue, Orders and MoM growth ?

WITH monthly_data AS (
SELECT
DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m')
AS order_month,
COUNT(DISTINCT o.order_id)
AS total_orders,
SUM(i.price) AS monthly_revenue FROM orders o
JOIN items i ON o.order_id = i.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY DATE_FORMAT(
o.order_purchase_timestamp, '%Y-%m'
)),
monthly_growth AS (
SELECT order_month,total_orders,monthly_revenue,
LAG(total_orders) OVER (
ORDER BY order_month
) AS previous_month_orders,
LAG(monthly_revenue) OVER (
ORDER BY order_month) AS previous_month_revenue
FROM monthly_data)
SELECT order_month,total_orders,
ROUND(monthly_revenue, 2) AS monthly_revenue,
previous_month_orders,
ROUND(
100.0 * (total_orders - previous_month_orders)/ NULLIF(previous_month_orders, 0),2) AS orders_mom_growth_pct,
ROUND(previous_month_revenue, 2)AS previous_month_revenue,
ROUND(100.0 * (monthly_revenue - previous_month_revenue)/ NULLIF(previous_month_revenue, 0),2) AS revenue_mom_growth_pct
FROM monthly_growth
ORDER BY order_month;

-- Q.5> What are the top 10 categories by Revenue ?

SELECT COALESCE(
g.product_category_name_english,
p.product_category_name,
'Unknown') 
AS product_category,
ROUND(SUM(i.price), 2) AS total_revenue,
SUM(i.order_item_id * 0 + 1) AS units_sold
FROM items i JOIN products p
ON i.product_id = p.product_id
LEFT JOIN category g
ON p.product_category_name = g.ï»¿product_category_name
GROUP BY COALESCE(
g.product_category_name_english,
p.product_category_name,'Unknown')
ORDER BY total_revenue DESC
LIMIT 10;


-- Q.6> What are the top 10 categories by Units ?

SELECT COALESCE(
g.product_category_name_english,
p.product_category_name,'Unknown') AS product_category,
COUNT(*) AS units_sold,
ROUND(SUM(i.price), 2) AS total_revenue
FROM items i JOIN products p
ON i.product_id = p.product_id
LEFT JOIN category g
ON p.product_category_name = g.ï»¿product_category_name
GROUP BY product_category
ORDER BY total_revenue DESC
LIMIT 10;

-- Q.7> What is the Revenue by customer state ?
-- seller-state → customer-state flow matrix.

WITH state_flows AS (
SELECT s.seller_state,c.customer_state,
SUM(i.price) AS revenue FROM items i
JOIN sellers s ON i.seller_id = s.seller_id
JOIN orders o ON i.order_id = o.order_id
JOIN customers c ON o.customer_id = c.customer_id
GROUP BY s.seller_state, c.customer_state)
SELECT seller_state,
ROUND(SUM(CASE WHEN customer_state = 'SP'
THEN revenue ELSE 0 END), 2) AS SP,
ROUND(SUM(CASE WHEN customer_state = 'RJ'
THEN revenue ELSE 0 END), 2) AS RJ,
ROUND(SUM(CASE WHEN customer_state = 'MG'
THEN revenue ELSE 0 END), 2) AS MG,
ROUND(SUM(CASE WHEN customer_state = 'PR'
THEN revenue ELSE 0 END), 2) AS PR,
ROUND(SUM(CASE WHEN customer_state = 'RS'
THEN revenue ELSE 0 END), 2) AS RS,
ROUND(SUM(CASE WHEN customer_state = 'BA'
THEN revenue ELSE 0 END), 2) AS BA FROM state_flows
GROUP BY seller_state
ORDER BY seller_state;

-- Q.8> Find black Friday vs normal-week revenue.

WITH order_revenue AS (
SELECT o.order_id,
DATE(o.order_purchase_timestamp) AS order_date,
YEAR(o.order_purchase_timestamp) AS order_year,
SUM(i.price) AS revenue
FROM orders o JOIN items i ON o.order_id = i.order_id
WHERE o.order_purchase_timestamp IS NOT NULL
GROUP BY o.order_id,
DATE(o.order_purchase_timestamp),
YEAR(o.order_purchase_timestamp)),
weekly_revenue AS (
SELECT order_year,
YEARWEEK(order_date, 3) AS year_week,
SUM(revenue) AS weekly_revenue FROM order_revenue
GROUP BY order_year,
YEARWEEK(order_date, 3)),
black_friday_dates AS (
SELECT 2016 AS order_year, '2016-11-25' AS bf_date
UNION ALL SELECT 2017, '2017-11-24'
UNION ALL SELECT 2018, '2018-11-23'),
bf_weeks AS (SELECT order_year,
YEARWEEK(DATE_SUB(DATE(bf_date),INTERVAL WEEKDAY(DATE(bf_date)) DAY),3) AS year_week
FROM black_friday_dates),comparison AS (SELECT w.order_year,
CASE WHEN b.year_week IS NOT NULL
THEN 'Black Friday Week' ELSE 'Normal Week' END AS week_type,w.weekly_revenue
FROM weekly_revenue w LEFT JOIN bf_weeks b ON w.order_year = b.order_year
AND w.year_week = b.year_week),annual_comparison AS (SELECT order_year,
AVG(CASE WHEN week_type = 'Black Friday Week' THEN weekly_revenue END) AS black_friday_revenue,
AVG(CASE WHEN week_type = 'Normal Week' THEN weekly_revenue END) AS avg_normal_week_revenue FROM comparison
GROUP BY order_year)SELECT order_year,
ROUND(black_friday_revenue, 2) AS black_friday_week_revenue,
ROUND(avg_normal_week_revenue, 2) AS avg_normal_week_revenue,
ROUND(100.0 * (black_friday_revenue - avg_normal_week_revenue) / NULLIF(avg_normal_week_revenue, 0),2) AS revenue_lift_pct
FROM annual_comparison
ORDER BY order_year;

-- Q.9> Find New customer VS Returning customers month wise.

WITH customer_orders AS(SELECT c.customer_unique_id,o.order_id,o.order_purchase_timestamp,
MIN(o.order_purchase_timestamp) OVER (PARTITION BY c.customer_unique_id) AS first_purchase
FROM orders o JOIN customers c ON o.customer_id = c.customer_id)
SELECT DATE_FORMAT(order_purchase_timestamp, '%Y-%m') AS month,
COUNT(DISTINCT CASE WHEN order_purchase_timestamp = first_purchase
THEN customer_unique_id END) AS new_customers,
COUNT(DISTINCT CASE WHEN order_purchase_timestamp > first_purchase
THEN customer_unique_id END) AS returning_customers FROM customer_orders
GROUP BY month
ORDER BY month;

-- Q.10> What is the Repeat Purchase rate?

WITH customer_orders AS (SELECT c.customer_unique_id,
COUNT(DISTINCT o.order_id) AS total_orders FROM orders o JOIN customers c ON o.customer_id = c.customer_id
GROUP BY c.customer_unique_id) 
SELECT COUNT(*) AS total_customers,
SUM(total_orders > 1) AS repeat_customers,
ROUND(100.0 * SUM(total_orders > 1) / COUNT(*), 2) AS repeat_purchase_rate_pct
FROM customer_orders;

-- Q.11> What is the RFM scoring ?

WITH rfm AS (SELECT c.customer_unique_id,
DATEDIFF((SELECT MAX(order_purchase_timestamp) FROM orders),
MAX(o.order_purchase_timestamp)) AS recency,
COUNT(DISTINCT o.order_id) AS frequency,
SUM(i.price) AS monetary FROM customers c
JOIN orders o ON c.customer_id = o.customer_id JOIN items i
ON o.order_id = i.order_id
GROUP BY c.customer_unique_id),
scores AS (SELECT *,
NTILE(5) OVER (ORDER BY recency DESC) AS R_score,
NTILE(5) OVER (ORDER BY frequency ASC) AS F_score,
NTILE(5) OVER (ORDER BY monetary ASC) AS M_score
FROM rfm)
SELECT *,CONCAT(R_score, F_score, M_score) AS RFM_score
FROM scores;

-- Q.12> What is the Order by payment type ?

SELECT payment_type,
ROUND(SUM(payment_value), 2) AS total_value,
ROUND(100.0 * SUM(payment_value) /SUM(SUM(payment_value)) OVER (), 2) AS payment_share_pct
FROM payments
GROUP BY payment_type
ORDER BY total_value DESC;

-- Q.13> Find the average installment by priceband.

WITH order_payments AS (SELECT order_id,
SUM(payment_value) AS order_value,
MAX(payment_installments) AS installments
FROM payments
GROUP BY order_id)
SELECT CASE WHEN order_value < 100 THEN 'Low (<100)'
WHEN order_value < 500 THEN 'Medium (100-499)'
ELSE 'High (500+)' END AS price_band,
COUNT(*) AS total_orders,
ROUND(AVG(installments), 2) AS avg_installments
FROM order_payments
GROUP BY price_band
ORDER BY MIN(order_value);

-- Q.14> Find the orders paid with 2+ methods.

WITH order_methods AS (SELECT order_id,
COUNT(DISTINCT payment_type) AS method_count FROM payments)
SELECT COUNT(*) AS total_orders,
SUM(method_count >= 2) AS multi_method_orders,
ROUND(100.0 * SUM(method_count >= 2) / COUNT(*), 2) AS multi_method_pct
FROM order_methods
GROUP BY method_count;

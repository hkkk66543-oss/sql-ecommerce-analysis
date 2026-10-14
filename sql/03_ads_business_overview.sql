-- MySQL 8.0; execute after CSV import and 02. Stop on the first SQL error.
-- No DROP / DELETE: existing ADS outputs are never overwritten by this script.
-- Re-run in a fresh database, or explicitly archive old ADS tables first.
USE olist_ecommerce;

-- Grain gate: DISTINCT order_id alone cannot fix inflated SUM(price).
-- Duplicate (order_id, order_item_id) rows must fail, not be silently deduplicated.
DROP TEMPORARY TABLE IF EXISTS tmp_business_items;
CREATE TEMPORARY TABLE tmp_business_items (
    order_id CHAR(32) NOT NULL,
    order_item_id INT NOT NULL,
    purchase_time DATETIME,
    price DECIMAL(15,2) NOT NULL,
    freight_value DECIMAL(15,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id)
);
INSERT INTO tmp_business_items
SELECT order_id, order_item_id,
       CASE
           WHEN order_purchase_timestamp REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} '
           THEN STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s')
           WHEN order_purchase_timestamp REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} '
           THEN STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i')
           ELSE NULL
       END,
       price, freight_value
FROM dwd_order_detail
WHERE order_status = 'delivered';

-- One row per delivered order WITH items; never join payment/review detail here.
DROP TEMPORARY TABLE IF EXISTS tmp_business_orders;
CREATE TEMPORARY TABLE tmp_business_orders AS
SELECT order_id, MIN(purchase_time) AS purchase_time,
       SUM(price) AS gmv, SUM(freight_value) AS total_freight
FROM tmp_business_items
GROUP BY order_id;
ALTER TABLE tmp_business_orders ADD PRIMARY KEY (order_id);

CREATE TABLE ads_business_overview AS
SELECT ROUND(SUM(gmv), 2) AS gmv,
       COUNT(*) AS order_count,
       ROUND(SUM(gmv) / NULLIF(COUNT(*), 0), 2) AS aov,
       ROUND(SUM(total_freight), 2) AS total_freight,
       ROUND(SUM(total_freight) / NULLIF(SUM(gmv), 0), 4) AS freight_ratio
FROM tmp_business_orders;

-- Sample covers Jan 2017 through Aug 2018; half-open purchase-date interval.
-- Overview includes all delivered history, so this subset will not sum to overview.
CREATE TABLE ads_monthly_business_trend_stable AS
SELECT DATE_FORMAT(purchase_time, '%Y-%m') AS order_month,
       ROUND(SUM(gmv), 2) AS gmv,
       COUNT(*) AS order_count,
       ROUND(SUM(gmv) / NULLIF(COUNT(*), 0), 2) AS aov,
       ROUND(SUM(total_freight), 2) AS total_freight,
       ROUND(SUM(total_freight) / NULLIF(SUM(gmv), 0), 4) AS freight_ratio
FROM tmp_business_orders
WHERE purchase_time >= '2017-01-01' AND purchase_time < '2018-09-01'
GROUP BY DATE_FORMAT(purchase_time, '%Y-%m');

-- All order statuses, including orders without items.
CREATE TABLE ads_order_status_analysis AS
SELECT order_status, COUNT(DISTINCT order_id) AS order_count,
       ROUND(COUNT(DISTINCT order_id) /
             NULLIF((SELECT COUNT(DISTINCT order_id) FROM orders), 0), 4) AS order_ratio
FROM orders
GROUP BY order_status;

-- All source payment rows, NOT delivered-only orders and NOT item-level joins.
-- payment_count = payment records; order_count = unique orders per payment type.
-- An order may use multiple types, so per-type order_count is not additive.
CREATE TABLE ads_payment_type_analysis AS
SELECT payment_type, COUNT(*) AS payment_count,
       COUNT(DISTINCT order_id) AS order_count,
       ROUND(SUM(payment_value), 2) AS payment_amount,
       ROUND(AVG(payment_value), 2) AS avg_payment_value
FROM order_payments
GROUP BY payment_type;

DROP TEMPORARY TABLE tmp_business_orders;
DROP TEMPORARY TABLE tmp_business_items;

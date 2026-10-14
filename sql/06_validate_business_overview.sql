-- Read-only checks. Run after 03; this file does not modify tables.
-- These queries have NOT been executed against the full Olist dataset in MySQL.
USE olist_ecommerce;

-- 1. Business keys: expect no rows. Never dedupe monetary values using SUM(DISTINCT).
SELECT order_id, order_item_id, COUNT(*) AS row_count
FROM dwd_order_detail GROUP BY order_id, order_item_id HAVING COUNT(*) > 1;
SELECT order_id, COUNT(*) AS row_count
FROM dwd_order_review_summary GROUP BY order_id HAVING COUNT(*) > 1;

-- 2. Orphans in critical joins: expect zero. Missing dimensions need investigation.
SELECT 'items_without_order' AS check_name, COUNT(*) AS issue_count
FROM order_items i LEFT JOIN orders o ON i.order_id = o.order_id WHERE o.order_id IS NULL
UNION ALL SELECT 'orders_without_customer', COUNT(*)
FROM orders o LEFT JOIN customers c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL
UNION ALL SELECT 'items_without_product', COUNT(*)
FROM order_items i LEFT JOIN products p ON i.product_id = p.product_id WHERE p.product_id IS NULL
UNION ALL SELECT 'items_without_seller', COUNT(*)
FROM order_items i LEFT JOIN sellers s ON i.seller_id = s.seller_id WHERE s.seller_id IS NULL
UNION ALL SELECT 'payments_without_order', COUNT(*)
FROM order_payments p LEFT JOIN orders o ON p.order_id = o.order_id WHERE o.order_id IS NULL;

-- 3. Item row preservation across the dimension/review joins: expect equal counts.
SELECT (SELECT COUNT(*) FROM order_items) AS source_items,
       (SELECT COUNT(*) FROM dwd_order_detail) AS dwd_items;
SELECT COUNT(*) AS delivered_orders_without_items
FROM orders o WHERE o.order_status = 'delivered'
AND NOT EXISTS (SELECT 1 FROM order_items i WHERE i.order_id = o.order_id);

-- 4. Independent ODS -> ADS reconciliation: expect all deltas zero.
WITH source_totals AS (
    SELECT SUM(i.price) AS gmv, COUNT(DISTINCT i.order_id) AS order_count,
           SUM(i.freight_value) AS total_freight
    FROM order_items i JOIN orders o ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
)
SELECT a.gmv - ROUND(s.gmv, 2) AS gmv_delta,
       a.order_count - s.order_count AS order_count_delta,
       a.total_freight - ROUND(s.total_freight, 2) AS freight_delta,
       a.aov - ROUND(s.gmv / NULLIF(s.order_count, 0), 2) AS aov_delta,
       a.freight_ratio - ROUND(s.total_freight / NULLIF(s.gmv, 0), 4) AS ratio_delta
FROM ads_business_overview a CROSS JOIN source_totals s;

-- 5. Full-history sample reference; differences are diagnostic, not proof of failure
-- until source version, import quality and delivered-order coverage are confirmed.
SELECT gmv - 13221498.11 AS sample_gmv_delta,
       order_count - 96478 AS sample_orders_delta,
       aov - 137.04 AS sample_aov_delta,
       total_freight - 2198275.64 AS sample_freight_delta,
       freight_ratio - 0.1663 AS sample_ratio_delta
FROM ads_business_overview;

-- 6. Date parsing coverage / item consistency: expect zero issues for valid imports.
WITH parsed AS (
    SELECT order_id,
           CASE
               WHEN order_purchase_timestamp REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2} '
               THEN STR_TO_DATE(order_purchase_timestamp, '%Y-%m-%d %H:%i:%s')
               WHEN order_purchase_timestamp REGEXP '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} '
               THEN STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i')
               ELSE NULL
           END AS purchase_time
    FROM dwd_order_detail WHERE order_status = 'delivered'
)
SELECT order_id, COUNT(*) AS item_count,
       SUM(purchase_time IS NULL) AS unparsed_items
FROM parsed GROUP BY order_id
HAVING SUM(purchase_time IS NULL) > 0 OR MIN(purchase_time) <> MAX(purchase_time);
SELECT COUNT(*) AS negative_amount_items
FROM order_items WHERE price < 0 OR freight_value < 0;

-- 7. Monthly sample subset total; do not compare to all-history overview.
SELECT SUM(gmv) - 13181027.13 AS sample_gmv_delta,
       SUM(order_count) - 96211 AS sample_orders_delta,
       SUM(total_freight) - 2192092.88 AS sample_freight_delta
FROM ads_monthly_business_trend_stable;
SELECT order_month FROM ads_monthly_business_trend_stable
WHERE aov <> ROUND(gmv / NULLIF(order_count, 0), 2)
   OR freight_ratio <> ROUND(total_freight / NULLIF(gmv, 0), 4);

-- Independent monthly ODS comparison: expect no missing months and zero deltas.
WITH source_months AS (
    SELECT DATE_FORMAT(STR_TO_DATE(o.order_purchase_timestamp, '%c/%e/%Y %H:%i'), '%Y-%m') AS order_month,
           SUM(i.price) AS gmv, COUNT(DISTINCT o.order_id) AS order_count,
           SUM(i.freight_value) AS total_freight
    FROM orders o JOIN order_items i ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
      AND STR_TO_DATE(o.order_purchase_timestamp, '%c/%e/%Y %H:%i') >= '2017-01-01'
      AND STR_TO_DATE(o.order_purchase_timestamp, '%c/%e/%Y %H:%i') < '2018-09-01'
    GROUP BY DATE_FORMAT(STR_TO_DATE(o.order_purchase_timestamp, '%c/%e/%Y %H:%i'), '%Y-%m')
)
SELECT s.order_month, a.order_month IS NULL AS missing_ads_month,
       a.gmv - ROUND(s.gmv, 2) AS gmv_delta,
       a.order_count - s.order_count AS orders_delta,
       a.total_freight - ROUND(s.total_freight, 2) AS freight_delta
FROM source_months s LEFT JOIN ads_monthly_business_trend_stable a USING (order_month);

-- 8. Different populations: status counts = all orders; payments = source rows.
SELECT (SELECT SUM(order_count) FROM ads_order_status_analysis) -
       (SELECT COUNT(*) FROM orders) AS status_orders_delta,
       (SELECT SUM(payment_count) FROM ads_payment_type_analysis) -
       (SELECT COUNT(*) FROM order_payments) AS payment_rows_delta,
       (SELECT SUM(payment_amount) FROM ads_payment_type_analysis) -
       (SELECT SUM(payment_value) FROM order_payments) AS payment_amount_delta;
SELECT order_status, order_count, order_ratio FROM ads_order_status_analysis ORDER BY order_count DESC;
SELECT payment_type, payment_count, order_count, payment_amount, avg_payment_value
FROM ads_payment_type_analysis ORDER BY payment_count DESC;

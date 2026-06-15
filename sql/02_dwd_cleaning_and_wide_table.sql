-- 1. 订单明细宽表
-- Navicat 查询：宽表
-- 输出表：dwd_order_detail
-- 作用：整合订单、商品、支付、用户、商家、品类等信息
USE olist_ecommerce;

DROP TABLE IF EXISTS dwd_order_detail;

CREATE TABLE dwd_order_detail AS
SELECT
    oi.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    oi.shipping_limit_date,
    oi.price,
    oi.freight_value,

    p.product_category_name,
    ct.product_category_name_english,
    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,

    s.seller_city,
    s.seller_state,

    r.review_score,
    r.review_creation_date,
    r.review_answer_timestamp,
    r.review_count
FROM order_items oi
LEFT JOIN orders o
    ON oi.order_id = o.order_id
LEFT JOIN customers c 
    ON o.customer_id = c.customer_id
LEFT JOIN products p 
    ON oi.product_id = p.product_id
LEFT JOIN category_translation ct 
    ON p.product_category_name = ct.product_category_name
LEFT JOIN sellers s 
    ON oi.seller_id = s.seller_id
LEFT JOIN dwd_order_review_summary r 
    ON oi.order_id = r.order_id;

-- 2. 物流明细表
-- Navicat 查询：物流明细表
-- 输出表：dwd_logistics_detail
-- 作用：整理订单创建、付款、发货、签收、预计送达等时间字段
USE olist_ecommerce;

DROP TABLE IF EXISTS dwd_logistics_detail;

CREATE TABLE dwd_logistics_detail AS
SELECT
    order_id,
    customer_id,
    customer_unique_id,
    customer_city,
    customer_state,
    seller_id,
    seller_city,
    seller_state,
    product_id,
    product_category_name,
    product_category_name_english,
    price,
    freight_value,
    review_score,

    order_status,

    STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i') AS purchase_time,
    STR_TO_DATE(order_approved_at, '%c/%e/%Y %H:%i') AS approved_time,
    STR_TO_DATE(order_delivered_carrier_date, '%c/%e/%Y %H:%i') AS carrier_time,
    STR_TO_DATE(order_delivered_customer_date, '%c/%e/%Y %H:%i') AS delivered_time,
    STR_TO_DATE(order_estimated_delivery_date, '%c/%e/%Y %H:%i') AS estimated_delivery_time,
    STR_TO_DATE(shipping_limit_date, '%c/%e/%Y %H:%i') AS shipping_limit_time,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_approved_at, '%c/%e/%Y %H:%i')
    ) AS payment_confirm_days,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_approved_at, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_delivered_carrier_date, '%c/%e/%Y %H:%i')
    ) AS seller_ship_days,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_delivered_carrier_date, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_delivered_customer_date, '%c/%e/%Y %H:%i')
    ) AS carrier_delivery_days,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_delivered_customer_date, '%c/%e/%Y %H:%i')
    ) AS total_delivery_days,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_estimated_delivery_date, '%c/%e/%Y %H:%i')
    ) AS estimated_delivery_days,

    CASE
        WHEN STR_TO_DATE(order_delivered_customer_date, '%c/%e/%Y %H:%i') 
             > STR_TO_DATE(order_estimated_delivery_date, '%c/%e/%Y %H:%i')
        THEN 1 ELSE 0
    END AS is_delivery_delayed,

    TIMESTAMPDIFF(
        DAY,
        STR_TO_DATE(order_estimated_delivery_date, '%c/%e/%Y %H:%i'),
        STR_TO_DATE(order_delivered_customer_date, '%c/%e/%Y %H:%i')
    ) AS delay_days,

    CASE
        WHEN STR_TO_DATE(order_delivered_carrier_date, '%c/%e/%Y %H:%i')
             > STR_TO_DATE(shipping_limit_date, '%c/%e/%Y %H:%i')
        THEN 1 ELSE 0
    END AS is_shipping_delayed

FROM dwd_order_detail
WHERE order_status = 'delivered'
  AND order_purchase_timestamp IS NOT NULL
  AND order_delivered_customer_date IS NOT NULL
  AND order_estimated_delivery_date IS NOT NULL;

-- 3. 清理后的物流明细表
-- Navicat 查询：清理后的物流明细表
-- 输出表：dwd_logistics_detail_clean
-- 作用：剔除异常时间、计算发货天数、配送天数、总配送天数
USE olist_ecommerce;

DROP TABLE IF EXISTS dwd_logistics_detail_clean;

CREATE TABLE dwd_logistics_detail_clean AS
SELECT *
FROM dwd_logistics_detail
WHERE total_delivery_days >= 0
  AND seller_ship_days >= 0;

-- 4. 评价汇总表
-- Navicat 查询：整体评分预览表
-- 输出表：dwd_order_review_summary
-- 作用：整理订单评分、好评/中评/差评标记
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_review_overview;

CREATE TABLE ads_review_overview AS
SELECT
    COUNT(DISTINCT order_id) AS reviewed_order_count,
    ROUND(AVG(review_score), 2) AS avg_review_score,
    ROUND(SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*), 4) AS bad_review_rate,
    ROUND(SUM(CASE WHEN review_score = 3 THEN 1 ELSE 0 END) / COUNT(*), 4) AS neutral_review_rate,
    ROUND(SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END) / COUNT(*), 4) AS good_review_rate
FROM dwd_order_detail
WHERE review_score IS NOT NULL
  AND order_status = 'delivered';

-- 5. 用户购买汇总表
-- Navicat 查询：用户购买汇总表
-- 输出表：dws_user_purchase_summary
-- 作用：按用户汇总购买次数、GMV、最近购买时间、平均评分等
USE olist_ecommerce;

DROP TABLE IF EXISTS dws_user_purchase_summary;

CREATE TABLE dws_user_purchase_summary AS
SELECT
    customer_unique_id,
    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(price), 2) AS total_gmv,
    ROUND(SUM(price) / COUNT(DISTINCT order_id), 2) AS avg_order_value,
    MIN(STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i')) AS first_purchase_time,
    MAX(STR_TO_DATE(order_purchase_timestamp, '%c/%e/%Y %H:%i')) AS last_purchase_time,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM dwd_order_detail
WHERE order_status = 'delivered'
  AND customer_unique_id IS NOT NULL
GROUP BY customer_unique_id;
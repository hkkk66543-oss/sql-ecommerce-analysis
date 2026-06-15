-- 1. 物流明细表
-- 输出表：dwd_logistics_detail
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

-- 2. 清理后的物流明细表
-- 输出表：dwd_logistics_detail_clean
USE olist_ecommerce;

DROP TABLE IF EXISTS dwd_logistics_detail_clean;

CREATE TABLE dwd_logistics_detail_clean AS
SELECT *
FROM dwd_logistics_detail
WHERE total_delivery_days >= 0
  AND seller_ship_days >= 0;

-- 3. 物流总览指标表
-- 输出表：ads_logistics_overview
-- 对应第二页 KPI：平均配送天数、商家发货天数、延迟送达率、差评率
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_logistics_overview;

CREATE TABLE ads_logistics_overview AS
SELECT
    COUNT(*) AS logistics_rows,

    ROUND(AVG(payment_confirm_days), 2) AS avg_payment_confirm_days,
    ROUND(AVG(seller_ship_days), 2) AS avg_seller_ship_days,
    ROUND(AVG(carrier_delivery_days), 2) AS avg_carrier_delivery_days,
    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,
    ROUND(AVG(estimated_delivery_days), 2) AS avg_estimated_delivery_days,

    ROUND(SUM(is_delivery_delayed) / COUNT(*), 4) AS delivery_delay_rate,
    ROUND(AVG(CASE WHEN is_delivery_delayed = 1 THEN delay_days END), 2) AS avg_delay_days,

    ROUND(SUM(is_shipping_delayed) / COUNT(*), 4) AS shipping_delay_rate
FROM dwd_logistics_detail_clean;

-- 4. 延迟送达对评分影响表
-- 输出表：ads_delay_review_impact
-- 对应第二页：延迟送达对平均评分、差评率的影响
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_delay_review_impact;

CREATE TABLE ads_delay_review_impact AS
SELECT
    CASE 
        WHEN is_delivery_delayed = 1 THEN 'delayed'
        ELSE 'not_delayed'
    END AS delivery_status,

    COUNT(DISTINCT order_id) AS order_count,
    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS bad_review_rate,

    ROUND(
        SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS good_review_rate,

    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days
FROM dwd_logistics_detail_clean
WHERE review_score IS NOT NULL
GROUP BY 
    CASE 
        WHEN is_delivery_delayed = 1 THEN 'delayed'
        ELSE 'not_delayed'
    END;

-- 5. 配送时长分组评分分析表
-- 输出表：ads_delivery_days_review_analysis
-- 对应第二页：配送时长与用户评分关系
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_delivery_days_review_analysis;

CREATE TABLE ads_delivery_days_review_analysis AS
SELECT
    CASE
        WHEN total_delivery_days <= 3 THEN '0-3 days'
        WHEN total_delivery_days <= 7 THEN '4-7 days'
        WHEN total_delivery_days <= 15 THEN '8-15 days'
        WHEN total_delivery_days <= 30 THEN '16-30 days'
        ELSE '30+ days'
    END AS delivery_days_group,

    COUNT(DISTINCT order_id) AS order_count,
    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS bad_review_rate,

    ROUND(
        SUM(CASE WHEN review_score >= 4 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS good_review_rate
FROM dwd_logistics_detail_clean
WHERE review_score IS NOT NULL
GROUP BY
    CASE
        WHEN total_delivery_days <= 3 THEN '0-3 days'
        WHEN total_delivery_days <= 7 THEN '4-7 days'
        WHEN total_delivery_days <= 15 THEN '8-15 days'
        WHEN total_delivery_days <= 30 THEN '16-30 days'
        ELSE '30+ days'
    END
ORDER BY 
    MIN(total_delivery_days);

-- 6. 客户地区物流表现表
-- 输出表：ads_logistics_by_customer_state
-- 对应第二页：延迟送达率最高地区 Top 10
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_logistics_by_customer_state;

CREATE TABLE ads_logistics_by_customer_state AS
SELECT
    customer_state,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,
    ROUND(AVG(carrier_delivery_days), 2) AS avg_carrier_delivery_days,

    ROUND(SUM(is_delivery_delayed) / COUNT(*), 4) AS delivery_delay_rate,
    ROUND(AVG(review_score), 2) AS avg_review_score
FROM dwd_logistics_detail_clean
GROUP BY customer_state
ORDER BY avg_total_delivery_days DESC;

-- 7. 商家物流履约分析表
-- 输出表：ads_seller_logistics_analysis
-- 对应第二页：高延迟商家样本 / 商家物流风险
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_seller_logistics_analysis;

CREATE TABLE ads_seller_logistics_analysis AS
SELECT
    seller_id,
    seller_city,
    seller_state,

    COUNT(DISTINCT order_id) AS order_count,
    ROUND(SUM(price), 2) AS gmv,

    ROUND(AVG(seller_ship_days), 2) AS avg_seller_ship_days,
    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,

    ROUND(SUM(is_shipping_delayed) / COUNT(*), 4) AS shipping_delay_rate,
    ROUND(SUM(is_delivery_delayed) / COUNT(*), 4) AS delivery_delay_rate,

    ROUND(AVG(review_score), 2) AS avg_review_score
FROM dwd_logistics_detail_clean
GROUP BY seller_id, seller_city, seller_state
HAVING order_count >= 50
ORDER BY delivery_delay_rate DESC;

-- 8. 高风险商家
-- 用于验证/展示高物流风险商家 Top 10
SELECT *
FROM ads_seller_logistics_analysis
ORDER BY delivery_delay_rate DESC
LIMIT 10;
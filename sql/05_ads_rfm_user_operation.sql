-- 1. 用户购买汇总表
-- 输出表：dws_user_purchase_summary
-- 用途：汇总每个用户的购买次数、GMV、客单价、首次/末次购买时间、平均评分
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

-- 2. 复购概览表
-- 输出表：ads_repurchase_overview
-- 对应第三页 KPI：用户数、复购用户数、复购率
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_repurchase_overview;

CREATE TABLE ads_repurchase_overview AS
SELECT
    COUNT(*) AS user_count,
    SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) AS repurchase_user_count,
    ROUND(SUM(CASE WHEN order_count >= 2 THEN 1 ELSE 0 END) / COUNT(*), 4) AS repurchase_rate,

    ROUND(SUM(total_gmv), 2) AS total_gmv,
    ROUND(SUM(CASE WHEN order_count >= 2 THEN total_gmv ELSE 0 END), 2) AS repurchase_user_gmv,
    ROUND(SUM(CASE WHEN order_count >= 2 THEN total_gmv ELSE 0 END) / SUM(total_gmv), 4) AS repurchase_gmv_ratio,

    ROUND(AVG(order_count), 2) AS avg_order_count_per_user,
    ROUND(AVG(total_gmv), 2) AS avg_gmv_per_user
FROM dws_user_purchase_summary;

-- 3. 购买频次分布表
-- 输出表：ads_user_purchase_frequency
-- 对应第三页：用户购买频次分布
USE olist_ecommerce;

DROP TABLE IF EXISTS ads_user_purchase_frequency;

CREATE TABLE ads_user_purchase_frequency AS
SELECT
    CASE
        WHEN order_count = 1 THEN '1 order'
        WHEN order_count = 2 THEN '2 orders'
        WHEN order_count = 3 THEN '3 orders'
        WHEN order_count >= 4 THEN '4+ orders'
    END AS purchase_frequency_group,
    COUNT(*) AS user_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM dws_user_purchase_summary), 4) AS user_ratio,
    ROUND(SUM(total_gmv), 2) AS gmv,
    ROUND(SUM(total_gmv) / (SELECT SUM(total_gmv) FROM dws_user_purchase_summary), 4) AS gmv_ratio
FROM dws_user_purchase_summary
GROUP BY
    CASE
        WHEN order_count = 1 THEN '1 order'
        WHEN order_count = 2 THEN '2 orders'
        WHEN order_count = 3 THEN '3 orders'
        WHEN order_count >= 4 THEN '4+ orders'
    END
ORDER BY
    CASE purchase_frequency_group
        WHEN '1 order' THEN 1
        WHEN '2 orders' THEN 2
        WHEN '3 orders' THEN 3
        WHEN '4+ orders' THEN 4
    END;

-- 4. RFM分析
-- 输出表：
-- dws_user_rfm_raw
-- dws_user_rfm_scored
-- dws_user_rfm
-- ads_rfm_user_segment
-- 对应第三页：RFM用户分层规模、RFM用户分层GMV贡献
USE olist_ecommerce;

/* =========================================================
   1. 创建 RFM 原始指标表
   粒度：一行代表一个真实用户 customer_unique_id

   R：距离分析日期最近一次购买的天数
   F：用户累计购买订单数
   M：用户累计消费金额
   ========================================================= */

DROP TABLE IF EXISTS dws_user_rfm_raw;

CREATE TABLE dws_user_rfm_raw AS
SELECT
    customer_unique_id,

    /* 分析日期：数据集最后购买日期的下一天 */
    DATE_ADD(
        (SELECT MAX(DATE(last_purchase_time))
         FROM dws_user_purchase_summary),
        INTERVAL 1 DAY
    ) AS analysis_date,

    first_purchase_time,
    last_purchase_time,

    /* R：最近一次购买距离分析日期的天数，越小越好 */
    DATEDIFF(
        DATE_ADD(
            (SELECT MAX(DATE(last_purchase_time))
             FROM dws_user_purchase_summary),
            INTERVAL 1 DAY
        ),
        DATE(last_purchase_time)
    ) AS recency_days,

    /* F：累计订单数，越大越好 */
    order_count AS frequency,

    /* M：累计消费金额，越大越好 */
    total_gmv AS monetary,

    avg_order_value,
    avg_review_score

FROM dws_user_purchase_summary
WHERE customer_unique_id IS NOT NULL
  AND last_purchase_time IS NOT NULL;


/* =========================================================
   2. 创建 RFM 打分表

   R 分数：按最近购买时间五等分
   M 分数：按累计消费金额五等分

   F 分数采用业务阈值，而不是五等分：
   你的平台 97% 用户只购买 1 次，直接使用 NTILE 会把相同购买
   次数的用户强行拆成不同分数，业务解释不合理。

   F 打分规则：
   1 次购买  = 1 分
   2 次购买  = 3 分
   3 次购买  = 4 分
   4 次及以上 = 5 分
   ========================================================= */

DROP TABLE IF EXISTS dws_user_rfm_scored;

CREATE TABLE dws_user_rfm_scored AS
SELECT
    customer_unique_id,
    analysis_date,
    first_purchase_time,
    last_purchase_time,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,

    /* 最近购买越近，R 分数越高 */
    NTILE(5) OVER (
        ORDER BY recency_days DESC
    ) AS r_score,

    /* 购买频次业务打分 */
    CASE
        WHEN frequency = 1 THEN 1
        WHEN frequency = 2 THEN 3
        WHEN frequency = 3 THEN 4
        WHEN frequency >= 4 THEN 5
        ELSE 1
    END AS f_score,

    /* 累计消费金额越高，M 分数越高 */
    NTILE(5) OVER (
        ORDER BY monetary ASC
    ) AS m_score

FROM dws_user_rfm_raw;


/* =========================================================
   3. 创建最终 RFM 用户分层表

   分层逻辑：
   - 高价值用户：最近购买、频次、金额均较高
   - 重要发展用户：近期购买、金额较高，但频次不足
   - 重要保持用户：频次和金额较高，但最近购买时间较远
   - 重要挽留用户：高频高消费，但长期未购买
   - 潜力用户：近期购买，有一定消费能力
   - 新用户：近期购买，但目前仅购买一次
   - 一般用户：价值表现中等
   - 流失风险用户：较长时间未购买
   ========================================================= */

DROP TABLE IF EXISTS dws_user_rfm;

CREATE TABLE dws_user_rfm AS
SELECT
    customer_unique_id,
    analysis_date,
    first_purchase_time,
    last_purchase_time,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,
    r_score,
    f_score,
    m_score,

    CONCAT(r_score, f_score, m_score) AS rfm_code,

    ROUND((r_score + f_score + m_score) / 3, 2) AS rfm_avg_score,

    CASE
        WHEN r_score >= 4
             AND f_score >= 4
             AND m_score >= 4
        THEN '高价值用户'

        WHEN r_score >= 4
             AND f_score <= 3
             AND m_score >= 4
        THEN '重要发展用户'

        WHEN r_score BETWEEN 2 AND 3
             AND f_score >= 4
             AND m_score >= 4
        THEN '重要保持用户'

        WHEN r_score = 1
             AND f_score >= 4
             AND m_score >= 4
        THEN '重要挽留用户'

        WHEN r_score >= 4
             AND m_score BETWEEN 2 AND 3
        THEN '潜力用户'

        WHEN r_score >= 4
             AND frequency = 1
             AND m_score <= 2
        THEN '新用户'

        WHEN r_score <= 2
             AND f_score <= 3
             AND m_score <= 3
        THEN '流失风险用户'

        ELSE '一般用户'
    END AS user_segment

FROM dws_user_rfm_scored;


/* =========================================================
   4. 创建 RFM 用户分层汇总表
   用于 Power BI 看板和业务分析
   ========================================================= */

DROP TABLE IF EXISTS ads_rfm_user_segment;

CREATE TABLE ads_rfm_user_segment AS
SELECT
    user_segment,

    COUNT(*) AS user_count,

    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM dws_user_rfm),
        4
    ) AS user_ratio,

    ROUND(SUM(monetary), 2) AS gmv,

    ROUND(
        SUM(monetary) / (SELECT SUM(monetary) FROM dws_user_rfm),
        4
    ) AS gmv_ratio,

    ROUND(AVG(recency_days), 2) AS avg_recency_days,

    ROUND(AVG(frequency), 2) AS avg_frequency,

    ROUND(AVG(monetary), 2) AS avg_monetary,

    ROUND(AVG(avg_order_value), 2) AS avg_order_value,

    ROUND(AVG(avg_review_score), 2) AS avg_review_score

FROM dws_user_rfm
GROUP BY user_segment
ORDER BY gmv DESC;


/* =========================================================
   5. 检查 RFM 表是否创建成功
   ========================================================= */

SELECT COUNT(*) AS rfm_user_count
FROM dws_user_rfm;

SELECT *
FROM ads_rfm_user_segment
ORDER BY gmv DESC;


/* =========================================================
   6. 查看高价值用户样例
   ========================================================= */

SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_code,
    user_segment
FROM dws_user_rfm
WHERE user_segment = '高价值用户'
ORDER BY monetary DESC
LIMIT 50;


/* =========================================================
   7. 查看流失风险用户样例
   ========================================================= */

SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    r_score,
    f_score,
    m_score,
    rfm_code,
    user_segment
FROM dws_user_rfm
WHERE user_segment = '流失风险用户'
ORDER BY monetary DESC
LIMIT 50;

-- 5. 流失客户
-- 输出表：dws_at_risk_user / dws_at_risk_order_summary
-- 用途：识别近期未活跃、存在流失风险的用户
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,
    rfm_code
FROM dws_user_rfm
WHERE user_segment = '流失风险用户'
ORDER BY monetary DESC;

-- 6. 流失风险用户分析
-- 输出表：
-- ads_at_risk_user_overview
-- ads_at_risk_user_priority_summary
-- ads_at_risk_user_category
-- ads_at_risk_user_state
-- 对应第三页：流失风险用户数、召回优先级、流失风险用户品类分析
USE olist_ecommerce;


/* =========================================================
   0. 前置检查：确认基础表存在
   这些只是检查语句，不创建表
   ========================================================= */

SHOW TABLES LIKE 'dwd_order_detail';
SHOW TABLES LIKE 'dwd_logistics_detail_clean';
SHOW TABLES LIKE 'dws_user_rfm';


/* =========================================================
   1. 创建流失风险用户名单
   粒度：一行 = 一个流失风险用户

   来源表：dws_user_rfm
   说明：
   dws_user_rfm 是用户级分层表，包含 customer_unique_id，
   可以用于和订单明细表关联。
   ========================================================= */

DROP TABLE IF EXISTS dws_at_risk_user;

CREATE TABLE dws_at_risk_user AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,
    r_score,
    f_score,
    m_score,
    rfm_code,
    user_segment
FROM dws_user_rfm
WHERE user_segment = '流失风险用户';


/* =========================================================
   2. 创建流失风险用户订单级汇总表
   粒度：一行 = 一个订单

   作用：
   1. 避免一个订单多个商品导致订单数重复
   2. 计算用户历史消费、地区、评分
   3. 后续用于地区分析和整体概览
   ========================================================= */

DROP TABLE IF EXISTS dws_at_risk_order_summary;

CREATE TABLE dws_at_risk_order_summary AS
SELECT
    d.order_id,
    d.customer_unique_id,

    MAX(d.customer_city) AS customer_city,
    MAX(d.customer_state) AS customer_state,

    MIN(d.order_purchase_timestamp) AS order_purchase_timestamp,

    ROUND(SUM(d.price), 2) AS order_gmv,
    ROUND(SUM(d.freight_value), 2) AS order_freight,

    MAX(d.review_score) AS review_score

FROM dwd_order_detail AS d
INNER JOIN dws_at_risk_user AS u
    ON d.customer_unique_id = u.customer_unique_id

WHERE d.order_status = 'delivered'
  AND d.customer_unique_id IS NOT NULL

GROUP BY
    d.order_id,
    d.customer_unique_id;


/* =========================================================
   3. 创建流失风险用户订单品类级汇总表
   粒度：一行 = 一个订单中的一个品类

   作用：
   分析流失风险用户过去主要买过哪些品类，
   为后续召回营销提供依据。
   ========================================================= */

DROP TABLE IF EXISTS dws_at_risk_order_category;

CREATE TABLE dws_at_risk_order_category AS
SELECT
    d.order_id,
    d.customer_unique_id,

    COALESCE(
        d.product_category_name_english,
        d.product_category_name,
        'unknown'
    ) AS category_name,

    ROUND(SUM(d.price), 2) AS category_gmv,
    ROUND(SUM(d.freight_value), 2) AS category_freight,

    MAX(d.review_score) AS review_score

FROM dwd_order_detail AS d
INNER JOIN dws_at_risk_user AS u
    ON d.customer_unique_id = u.customer_unique_id

WHERE d.order_status = 'delivered'
  AND d.customer_unique_id IS NOT NULL

GROUP BY
    d.order_id,
    d.customer_unique_id,
    COALESCE(
        d.product_category_name_english,
        d.product_category_name,
        'unknown'
    );


/* =========================================================
   4. 创建流失风险用户物流订单级汇总表
   粒度：一行 = 一个订单

   来源表：dwd_logistics_detail_clean
   说明：
   只使用已经清洗过异常值的物流表。
   ========================================================= */

DROP TABLE IF EXISTS dws_at_risk_order_logistics;

CREATE TABLE dws_at_risk_order_logistics AS
SELECT
    l.order_id,
    l.customer_unique_id,

    MAX(l.customer_state) AS customer_state,

    MAX(l.seller_ship_days) AS seller_ship_days,
    MAX(l.carrier_delivery_days) AS carrier_delivery_days,
    MAX(l.total_delivery_days) AS total_delivery_days,

    MAX(l.is_shipping_delayed) AS is_shipping_delayed,
    MAX(l.is_delivery_delayed) AS is_delivery_delayed,

    MAX(l.review_score) AS review_score

FROM dwd_logistics_detail_clean AS l
INNER JOIN dws_at_risk_user AS u
    ON l.customer_unique_id = u.customer_unique_id

WHERE l.customer_unique_id IS NOT NULL

GROUP BY
    l.order_id,
    l.customer_unique_id;


/* =========================================================
   5. 流失风险用户整体概览
   粒度：一行 = 流失风险用户整体

   核心指标：
   用户数、订单数、GMV、客单价、平均流失间隔、平均评分
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_overview;

CREATE TABLE ads_at_risk_user_overview AS
SELECT
    COUNT(DISTINCT u.customer_unique_id) AS user_count,

    COUNT(DISTINCT o.order_id) AS order_count,

    ROUND(SUM(o.order_gmv), 2) AS total_gmv,

    ROUND(
        SUM(o.order_gmv) / COUNT(DISTINCT o.order_id),
        2
    ) AS aov,

    ROUND(AVG(u.recency_days), 2) AS avg_recency_days,
    ROUND(AVG(u.frequency), 2) AS avg_frequency,
    ROUND(AVG(u.monetary), 2) AS avg_monetary,
    ROUND(AVG(u.avg_order_value), 2) AS avg_order_value,

    ROUND(AVG(u.avg_review_score), 2) AS avg_review_score

FROM dws_at_risk_user AS u
LEFT JOIN dws_at_risk_order_summary AS o
    ON u.customer_unique_id = o.customer_unique_id;


/* =========================================================
   6. 流失风险用户召回优先级表
   粒度：一行 = 一个流失风险用户

   业务逻辑：
   流失风险用户很多，不可能全部同等成本召回。
   所以按历史累计消费金额 monetary 划分优先级。
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_priority;

CREATE TABLE ads_at_risk_user_priority AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,
    r_score,
    f_score,
    m_score,
    rfm_code,

    CASE
        WHEN monetary >= 200 THEN '高优先级召回'
        WHEN monetary >= 100 THEN '中优先级召回'
        ELSE '低优先级召回'
    END AS recall_priority

FROM dws_at_risk_user
ORDER BY monetary DESC;


/* =========================================================
   7. 流失风险用户召回优先级汇总
   粒度：一行 = 一个召回优先级

   用于判断：
   高、中、低优先级召回人群各有多少人，
   历史贡献 GMV 分别是多少。
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_priority_summary;

CREATE TABLE ads_at_risk_user_priority_summary AS
SELECT
    recall_priority,

    COUNT(*) AS user_count,

    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM ads_at_risk_user_priority),
        4
    ) AS user_ratio,

    ROUND(SUM(monetary), 2) AS total_gmv,

    ROUND(
        SUM(monetary) / (SELECT SUM(monetary) FROM ads_at_risk_user_priority),
        4
    ) AS gmv_ratio,

    ROUND(AVG(recency_days), 2) AS avg_recency_days,
    ROUND(AVG(frequency), 2) AS avg_frequency,
    ROUND(AVG(monetary), 2) AS avg_monetary,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score

FROM ads_at_risk_user_priority

GROUP BY recall_priority

ORDER BY total_gmv DESC;


/* =========================================================
   8. 流失风险用户品类偏好分析
   粒度：一行 = 一个品类

   指标解释：
   user_count：买过该品类的流失风险用户数
   user_penetration_rate：该品类在流失风险用户中的渗透率
   total_gmv：该品类历史贡献 GMV
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_category;

CREATE TABLE ads_at_risk_user_category AS
SELECT
    category_name,

    COUNT(DISTINCT customer_unique_id) AS user_count,

    ROUND(
        COUNT(DISTINCT customer_unique_id) /
        (SELECT COUNT(*) FROM dws_at_risk_user),
        4
    ) AS user_penetration_rate,

    COUNT(DISTINCT order_id) AS order_count,

    ROUND(SUM(category_gmv), 2) AS total_gmv,

    ROUND(
        SUM(category_gmv) /
        (SELECT SUM(order_gmv) FROM dws_at_risk_order_summary),
        4
    ) AS gmv_ratio,

    ROUND(
        SUM(category_gmv) / COUNT(DISTINCT order_id),
        2
    ) AS aov,

    ROUND(AVG(review_score), 2) AS avg_review_score

FROM dws_at_risk_order_category

GROUP BY category_name

ORDER BY total_gmv DESC;


/* =========================================================
   9. 流失风险用户地区分布分析
   粒度：一行 = 一个客户州

   用于判断：
   流失风险用户主要集中在哪些地区。
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_state;

CREATE TABLE ads_at_risk_user_state AS
SELECT
    customer_state,

    COUNT(DISTINCT customer_unique_id) AS user_count,

    ROUND(
        COUNT(DISTINCT customer_unique_id) /
        (SELECT COUNT(*) FROM dws_at_risk_user),
        4
    ) AS user_penetration_rate,

    COUNT(DISTINCT order_id) AS order_count,

    ROUND(SUM(order_gmv), 2) AS total_gmv,

    ROUND(
        SUM(order_gmv) /
        (SELECT SUM(order_gmv) FROM dws_at_risk_order_summary),
        4
    ) AS gmv_ratio,

    ROUND(
        SUM(order_gmv) / COUNT(DISTINCT order_id),
        2
    ) AS aov,

    ROUND(AVG(review_score), 2) AS avg_review_score

FROM dws_at_risk_order_summary

WHERE customer_state IS NOT NULL

GROUP BY customer_state

ORDER BY user_count DESC;


/* =========================================================
   10. 流失风险用户地区 × 品类交叉分析
   粒度：一行 = 一个州的一个品类

   用途：
   后续 Power BI 可以做矩阵表或热力图。
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_state_category;

CREATE TABLE ads_at_risk_user_state_category AS
SELECT
    o.customer_state,
    c.category_name,

    COUNT(DISTINCT c.customer_unique_id) AS user_count,
    COUNT(DISTINCT c.order_id) AS order_count,

    ROUND(SUM(c.category_gmv), 2) AS total_gmv,

    ROUND(
        SUM(c.category_gmv) / COUNT(DISTINCT c.order_id),
        2
    ) AS aov,

    ROUND(AVG(c.review_score), 2) AS avg_review_score

FROM dws_at_risk_order_category AS c
INNER JOIN dws_at_risk_order_summary AS o
    ON c.order_id = o.order_id

WHERE o.customer_state IS NOT NULL

GROUP BY
    o.customer_state,
    c.category_name

ORDER BY total_gmv DESC;


/* =========================================================
   11. 流失风险用户物流体验概览
   粒度：一行 = 流失风险用户整体

   核心问题：
   流失风险用户是否经历了更差的物流体验？
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_logistics;

CREATE TABLE ads_at_risk_user_logistics AS
SELECT
    COUNT(DISTINCT customer_unique_id) AS user_count,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(AVG(seller_ship_days), 2) AS avg_seller_ship_days,
    ROUND(AVG(carrier_delivery_days), 2) AS avg_carrier_delivery_days,
    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,

    ROUND(
        SUM(is_shipping_delayed) / COUNT(*),
        4
    ) AS shipping_delay_rate,

    ROUND(
        SUM(is_delivery_delayed) / COUNT(*),
        4
    ) AS delivery_delay_rate,

    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score < 3 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS bad_review_rate

FROM dws_at_risk_order_logistics;


/* =========================================================
   12. 流失风险用户地区物流表现
   粒度：一行 = 一个客户州

   用途：
   判断哪些地区的流失风险用户物流体验更差。
   ========================================================= */

DROP TABLE IF EXISTS ads_at_risk_user_state_logistics;

CREATE TABLE ads_at_risk_user_state_logistics AS
SELECT
    customer_state,

    COUNT(DISTINCT customer_unique_id) AS user_count,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,

    ROUND(
        SUM(is_delivery_delayed) / COUNT(*),
        4
    ) AS delivery_delay_rate,

    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score < 3 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS bad_review_rate

FROM dws_at_risk_order_logistics

WHERE customer_state IS NOT NULL

GROUP BY customer_state

ORDER BY delivery_delay_rate DESC;

-- 7. 高价值用户品类、地域、复购分析
-- 输出表：
-- ads_high_value_user_overview
-- ads_high_value_user_category
-- ads_high_value_user_state
-- ads_high_value_user_frequency
-- 对应第三页：高价值用户数、高价值用户Top品类
USE olist_ecommerce;


/* =========================================================
   一、高价值用户名单
   粒度：一行 = 一个高价值用户
   ========================================================= */

DROP TABLE IF EXISTS dws_high_value_user;

CREATE TABLE dws_high_value_user AS
SELECT
    customer_unique_id,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    avg_review_score,
    r_score,
    f_score,
    m_score,
    rfm_code,
    user_segment
FROM dws_user_rfm
WHERE user_segment = '高价值用户';


/* =========================================================
   二、高价值用户订单级汇总表
   粒度：一行 = 一个订单

   作用：
   1. 避免一个订单有多个商品导致订单数重复
   2. 避免评分被商品明细重复加权
   ========================================================= */

DROP TABLE IF EXISTS dws_high_value_order_summary;

CREATE TABLE dws_high_value_order_summary AS
SELECT
    d.order_id,
    d.customer_unique_id,

    MAX(d.customer_city) AS customer_city,
    MAX(d.customer_state) AS customer_state,

    MIN(d.order_purchase_timestamp) AS order_purchase_timestamp,

    ROUND(SUM(d.price), 2) AS order_gmv,
    ROUND(SUM(d.freight_value), 2) AS order_freight,

    MAX(d.review_score) AS review_score

FROM dwd_order_detail AS d
INNER JOIN dws_high_value_user AS u
    ON d.customer_unique_id = u.customer_unique_id

WHERE d.order_status = 'delivered'
  AND d.customer_unique_id IS NOT NULL

GROUP BY
    d.order_id,
    d.customer_unique_id;


/* =========================================================
   三、高价值用户订单品类级汇总表
   粒度：一行 = 一个订单中的一个品类

   作用：
   避免同一订单内相同品类的多个商品导致订单数重复
   ========================================================= */

DROP TABLE IF EXISTS dws_high_value_order_category;

CREATE TABLE dws_high_value_order_category AS
SELECT
    d.order_id,
    d.customer_unique_id,

    COALESCE(
        d.product_category_name_english,
        d.product_category_name,
        'unknown'
    ) AS category_name,

    ROUND(SUM(d.price), 2) AS category_gmv,
    ROUND(SUM(d.freight_value), 2) AS category_freight,

    MAX(d.review_score) AS review_score

FROM dwd_order_detail AS d
INNER JOIN dws_high_value_user AS u
    ON d.customer_unique_id = u.customer_unique_id

WHERE d.order_status = 'delivered'
  AND d.customer_unique_id IS NOT NULL

GROUP BY
    d.order_id,
    d.customer_unique_id,
    COALESCE(
        d.product_category_name_english,
        d.product_category_name,
        'unknown'
    );


/* =========================================================
   四、高价值用户订单商家级汇总表
   粒度：一行 = 一个订单中的一个商家
   ========================================================= */

DROP TABLE IF EXISTS dws_high_value_order_seller;

CREATE TABLE dws_high_value_order_seller AS
SELECT
    d.order_id,
    d.customer_unique_id,

    d.seller_id,
    MAX(d.seller_city) AS seller_city,
    MAX(d.seller_state) AS seller_state,

    ROUND(SUM(d.price), 2) AS seller_gmv,
    ROUND(SUM(d.freight_value), 2) AS seller_freight,

    MAX(d.review_score) AS review_score

FROM dwd_order_detail AS d
INNER JOIN dws_high_value_user AS u
    ON d.customer_unique_id = u.customer_unique_id

WHERE d.order_status = 'delivered'
  AND d.customer_unique_id IS NOT NULL
  AND d.seller_id IS NOT NULL

GROUP BY
    d.order_id,
    d.customer_unique_id,
    d.seller_id;


/* =========================================================
   五、高价值用户物流订单级汇总表
   粒度：一行 = 一个订单

   作用：
   分析高价值用户的物流体验
   ========================================================= */

DROP TABLE IF EXISTS dws_high_value_order_logistics;

CREATE TABLE dws_high_value_order_logistics AS
SELECT
    l.order_id,
    l.customer_unique_id,

    MAX(l.customer_state) AS customer_state,

    MAX(l.seller_ship_days) AS seller_ship_days,
    MAX(l.carrier_delivery_days) AS carrier_delivery_days,
    MAX(l.total_delivery_days) AS total_delivery_days,

    MAX(l.is_shipping_delayed) AS is_shipping_delayed,
    MAX(l.is_delivery_delayed) AS is_delivery_delayed,

    MAX(l.review_score) AS review_score

FROM dwd_logistics_detail_clean AS l
INNER JOIN dws_high_value_user AS u
    ON l.customer_unique_id = u.customer_unique_id

WHERE l.customer_unique_id IS NOT NULL

GROUP BY
    l.order_id,
    l.customer_unique_id;


/* =========================================================
   六、高价值用户整体经营概览
   粒度：一行 = 高价值用户整体
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_overview;

CREATE TABLE ads_high_value_user_overview AS
SELECT
    COUNT(*) AS user_count,

    ROUND(AVG(recency_days), 2) AS avg_recency_days,
    ROUND(AVG(frequency), 2) AS avg_frequency,
    ROUND(AVG(monetary), 2) AS avg_monetary,
    ROUND(AVG(avg_order_value), 2) AS avg_order_value,
    ROUND(AVG(avg_review_score), 2) AS avg_review_score,

    ROUND(SUM(monetary), 2) AS total_gmv

FROM dws_high_value_user;


/* =========================================================
   七、高价值用户购买频次分布
   粒度：一行 = 一个购买频次区间
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_frequency;

CREATE TABLE ads_high_value_user_frequency AS
SELECT
    CASE
        WHEN frequency = 1 THEN '1 order'
        WHEN frequency = 2 THEN '2 orders'
        WHEN frequency = 3 THEN '3 orders'
        WHEN frequency = 4 THEN '4 orders'
        ELSE '5+ orders'
    END AS frequency_group,

    COUNT(*) AS user_count,

    ROUND(
        COUNT(*) / (SELECT COUNT(*) FROM dws_high_value_user),
        4
    ) AS user_ratio,

    ROUND(SUM(monetary), 2) AS total_gmv,

    ROUND(
        SUM(monetary) / (SELECT SUM(monetary) FROM dws_high_value_user),
        4
    ) AS gmv_ratio

FROM dws_high_value_user

GROUP BY
    CASE
        WHEN frequency = 1 THEN '1 order'
        WHEN frequency = 2 THEN '2 orders'
        WHEN frequency = 3 THEN '3 orders'
        WHEN frequency = 4 THEN '4 orders'
        ELSE '5+ orders'
    END

ORDER BY
    MIN(frequency);


/* =========================================================
   八、高价值用户品类偏好分析
   粒度：一行 = 一个品类

   指标说明：
   user_penetration_rate：
   购买过该品类的高价值用户占全部高价值用户的比例

   order_penetration_rate：
   包含该品类的订单占全部高价值用户订单的比例
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_category;

CREATE TABLE ads_high_value_user_category AS
SELECT
    c.category_name,

    COUNT(DISTINCT c.customer_unique_id) AS user_count,

    ROUND(
        COUNT(DISTINCT c.customer_unique_id) /
        (SELECT COUNT(*) FROM dws_high_value_user),
        4
    ) AS user_penetration_rate,

    COUNT(DISTINCT c.order_id) AS order_count,

    ROUND(
        COUNT(DISTINCT c.order_id) /
        (SELECT COUNT(*) FROM dws_high_value_order_summary),
        4
    ) AS order_penetration_rate,

    ROUND(SUM(c.category_gmv), 2) AS total_gmv,

    ROUND(
        SUM(c.category_gmv) /
        (SELECT SUM(order_gmv) FROM dws_high_value_order_summary),
        4
    ) AS gmv_ratio,

    ROUND(
        SUM(c.category_gmv) / COUNT(DISTINCT c.order_id),
        2
    ) AS aov,

    ROUND(
        SUM(c.category_freight) / SUM(c.category_gmv),
        4
    ) AS freight_ratio,

    ROUND(AVG(c.review_score), 2) AS avg_review_score

FROM dws_high_value_order_category AS c

GROUP BY c.category_name

ORDER BY total_gmv DESC;


/* =========================================================
   九、高价值用户地区分布分析
   粒度：一行 = 一个客户州
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_state;

CREATE TABLE ads_high_value_user_state AS
SELECT
    customer_state,

    COUNT(DISTINCT customer_unique_id) AS user_count,

    ROUND(
        COUNT(DISTINCT customer_unique_id) /
        (SELECT COUNT(*) FROM dws_high_value_user),
        4
    ) AS user_ratio,

    COUNT(DISTINCT order_id) AS order_count,

    ROUND(SUM(order_gmv), 2) AS total_gmv,

    ROUND(
        SUM(order_gmv) /
        (SELECT SUM(order_gmv) FROM dws_high_value_order_summary),
        4
    ) AS gmv_ratio,

    ROUND(
        SUM(order_gmv) / COUNT(DISTINCT order_id),
        2
    ) AS aov,

    ROUND(AVG(review_score), 2) AS avg_review_score

FROM dws_high_value_order_summary

WHERE customer_state IS NOT NULL

GROUP BY customer_state

ORDER BY total_gmv DESC;


/* =========================================================
   十、高价值用户地区 × 品类交叉分析
   粒度：一行 = 一个州的一个品类

   用途：
   Power BI 热力图、地区差异化营销
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_state_category;

CREATE TABLE ads_high_value_user_state_category AS
SELECT
    o.customer_state,
    c.category_name,

    COUNT(DISTINCT c.customer_unique_id) AS user_count,
    COUNT(DISTINCT c.order_id) AS order_count,

    ROUND(SUM(c.category_gmv), 2) AS total_gmv,

    ROUND(
        SUM(c.category_gmv) / COUNT(DISTINCT c.order_id),
        2
    ) AS aov,

    ROUND(AVG(c.review_score), 2) AS avg_review_score

FROM dws_high_value_order_category AS c
INNER JOIN dws_high_value_order_summary AS o
    ON c.order_id = o.order_id

WHERE o.customer_state IS NOT NULL

GROUP BY
    o.customer_state,
    c.category_name

ORDER BY total_gmv DESC;


/* =========================================================
   十一、高价值用户商家偏好分析
   粒度：一行 = 一个商家
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_seller;

CREATE TABLE ads_high_value_user_seller AS
SELECT
    seller_id,
    seller_city,
    seller_state,

    COUNT(DISTINCT customer_unique_id) AS user_count,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(SUM(seller_gmv), 2) AS total_gmv,

    ROUND(
        SUM(seller_gmv) /
        (SELECT SUM(order_gmv) FROM dws_high_value_order_summary),
        4
    ) AS gmv_ratio,

    ROUND(
        SUM(seller_gmv) / COUNT(DISTINCT order_id),
        2
    ) AS aov,

    ROUND(AVG(review_score), 2) AS avg_review_score

FROM dws_high_value_order_seller

GROUP BY
    seller_id,
    seller_city,
    seller_state

ORDER BY total_gmv DESC;


/* =========================================================
   十二、高价值用户物流体验概览
   粒度：一行 = 高价值用户整体
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_logistics_overview;

CREATE TABLE ads_high_value_user_logistics_overview AS
SELECT
    COUNT(DISTINCT customer_unique_id) AS user_count,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(AVG(seller_ship_days), 2) AS avg_seller_ship_days,
    ROUND(AVG(carrier_delivery_days), 2) AS avg_carrier_delivery_days,
    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,

    ROUND(
        SUM(is_shipping_delayed) / COUNT(*),
        4
    ) AS shipping_delay_rate,

    ROUND(
        SUM(is_delivery_delayed) / COUNT(*),
        4
    ) AS delivery_delay_rate,

    ROUND(AVG(review_score), 2) AS avg_review_score,

    ROUND(
        SUM(CASE WHEN review_score < 3 THEN 1 ELSE 0 END) / COUNT(*),
        4
    ) AS bad_review_rate

FROM dws_high_value_order_logistics;


/* =========================================================
   十三、高价值用户地区物流体验
   粒度：一行 = 一个客户州
   ========================================================= */

DROP TABLE IF EXISTS ads_high_value_user_state_logistics;

CREATE TABLE ads_high_value_user_state_logistics AS
SELECT
    customer_state,

    COUNT(DISTINCT customer_unique_id) AS user_count,
    COUNT(DISTINCT order_id) AS order_count,

    ROUND(AVG(total_delivery_days), 2) AS avg_total_delivery_days,

    ROUND(
        SUM(is_delivery_delayed) / COUNT(*),
        4
    ) AS delivery_delay_rate,

    ROUND(AVG(review_score), 2) AS avg_review_score

FROM dws_high_value_order_logistics

WHERE customer_state IS NOT NULL

GROUP BY customer_state

ORDER BY delivery_delay_rate DESC;








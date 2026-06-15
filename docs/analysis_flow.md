# 项目分析流程说明

## 1. 项目整体流程

本项目基于 Kaggle 平台公开的 Olist 巴西电商数据集，围绕电商平台经营表现、物流履约体验和用户运营价值三个方向进行分析。

整体流程如下：

```text
原始 CSV 数据
→ MySQL 建表导入
→ ODS 原始数据层
→ DWD 清洗明细层
→ ADS 指标汇总层
→ Power BI 三页可视化看板
→ 业务洞察输出
```

本项目重点体现从原始多表数据到业务指标建模，再到可视化分析和经营洞察输出的完整数据分析流程。

---

## 2. 数据来源

本项目使用 Kaggle 公开数据集：

```text
Brazilian E-Commerce Public Dataset by Olist
```

数据集地址：

```text
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```

该数据集包含巴西电商平台 Olist 的订单、商品、支付、评价、客户、商家、地理位置等多张业务表，适合用于电商经营分析、用户分析、物流分析和评价分析。

本项目未将完整原始 CSV 文件上传至 GitHub，仅在 README 中保留数据来源链接，并在 `data_sample/` 文件夹中保留 SQL 生成后的 ADS 汇总样例表。

---

## 3. 原始数据表

原始数据导入 MySQL 后，主要包括以下业务表：

```text
customers
orders
order_items
order_payments
order_reviews
products
sellers
geolocation
category_translation
```

各表含义如下：

| 表名                   | 含义                                           |
| -------------------- | -------------------------------------------- |
| customers            | 客户信息表，包含客户 ID、唯一用户 ID、城市、州等信息                |
| orders               | 订单主表，包含订单 ID、客户 ID、订单状态、下单时间、付款时间、发货时间、签收时间等 |
| order_items          | 订单明细表，包含订单商品、卖家、价格、运费等信息                     |
| order_payments       | 订单支付表，包含支付方式、支付金额、分期数等信息                     |
| order_reviews        | 订单评价表，包含评分、评价时间、评论内容等信息                      |
| products             | 商品信息表，包含商品 ID、品类、尺寸、重量等信息                    |
| sellers              | 商家信息表，包含商家 ID、城市、州等信息                        |
| geolocation          | 地理位置表，包含邮编、经纬度、城市、州等信息                       |
| category_translation | 商品品类翻译表，用于将葡萄牙语品类名转换为英文品类名                   |

---

## 4. MySQL 建表与数据导入

项目首先在 MySQL 中创建数据库：

```sql
CREATE DATABASE IF NOT EXISTS olist_ecommerce;
USE olist_ecommerce;
```

随后将 Kaggle 下载的原始 CSV 文件导入 MySQL，对应生成原始业务表。

导入完成后，对表名进行规范化处理，使后续 SQL 编写更加清晰。例如：

```text
olist_orders_dataset → orders
olist_order_items_dataset → order_items
olist_order_payments_dataset → order_payments
olist_order_reviews_dataset → order_reviews
```

这一阶段的目标是完成原始数据入库，为后续多表关联、数据清洗和指标计算提供基础。

---

## 5. 数据分层设计

本项目采用常见的数据仓库分层思想，将数据处理过程分为 ODS、DWD、ADS 三层。

### 5.1 ODS 原始数据层

ODS 层用于保存从 CSV 文件导入 MySQL 后的原始数据表。

该层基本不做复杂加工，主要保留原始字段和原始业务记录。

主要表包括：

```text
orders
order_items
order_payments
order_reviews
customers
products
sellers
geolocation
category_translation
```

ODS 层的作用是保证原始数据可追溯。

---

### 5.2 DWD 清洗明细层

DWD 层用于对原始业务表进行清洗、关联和字段加工，形成后续分析可直接使用的明细宽表。

本项目主要生成以下 DWD / DWS 表：

```text
dwd_order_detail
dwd_logistics_detail
dwd_logistics_detail_clean
dwd_order_review_summary
dws_user_purchase_summary
```

其中：

| 表名                         | 作用                                 |
| -------------------------- | ---------------------------------- |
| dwd_order_detail           | 订单明细宽表，整合订单、商品、支付、用户、商家、品类等信息      |
| dwd_logistics_detail       | 物流明细表，整理订单下单、付款、发货、签收、预计送达等时间字段    |
| dwd_logistics_detail_clean | 清洗后的物流明细表，剔除异常时间并计算配送相关天数          |
| dwd_order_review_summary   | 订单评价汇总表，整理评分、好评、中评、差评等标记           |
| dws_user_purchase_summary  | 用户购买汇总表，按用户汇总购买次数、GMV、最近购买时间、平均评分等 |

DWD 层主要解决以下问题：

```text
1. 多表字段分散，无法直接分析
2. 原始时间字段需要转换和计算
3. 订单、商品、支付、评价、物流、用户信息需要统一到分析粒度
4. 后续 ADS 指标表需要稳定的数据基础
```

---

## 6. 数据清洗与字段加工

在 DWD 层中，项目主要进行了以下清洗和加工操作。

### 6.1 多表关联

将订单主表、订单明细表、支付表、评价表、客户表、商家表、商品表和品类翻译表进行关联，形成订单明细宽表。

主要关联逻辑包括：

```text
orders.order_id = order_items.order_id
orders.order_id = order_payments.order_id
orders.order_id = order_reviews.order_id
orders.customer_id = customers.customer_id
order_items.product_id = products.product_id
order_items.seller_id = sellers.seller_id
products.product_category_name = category_translation.product_category_name
```

---

### 6.2 时间字段处理

对订单中的时间字段进行统一处理，包括：

```text
order_purchase_timestamp
order_approved_at
order_delivered_carrier_date
order_delivered_customer_date
order_estimated_delivery_date
```

并进一步计算物流时效指标：

```text
付款确认天数
商家发货天数
承运配送天数
总配送天数
预计配送天数
延迟天数
```

---

### 6.3 异常物流数据清洗

在物流分析中，主要剔除或处理以下异常情况：

```text
签收时间缺失
发货时间缺失
付款时间缺失
签收时间早于下单时间
发货时间早于付款时间
配送天数异常过大或异常为负
```

清洗后的结果用于生成：

```text
dwd_logistics_detail_clean
```

该表作为物流履约页面的基础数据表。

---

### 6.4 评价数据处理

订单评价表中的原始评分字段为：

```text
review_score
```

取值范围为 1 到 5 的整数。

项目基于评分生成评价类型：

```text
差评：review_score <= 2
中评：review_score = 3
好评：review_score >= 4
```

后续看板中的平均评分为聚合后的平均值，因此可能出现小数，例如 4.08、4.33、2.55 等。

---

### 6.5 用户购买行为汇总

基于用户唯一 ID：

```text
customer_unique_id
```

对用户购买行为进行汇总，计算：

```text
用户订单数
用户GMV
用户客单价
首次购买时间
最近购买时间
平均评分
购买频次
```

该结果用于后续复购分析、RFM 用户分层和流失风险识别。

---

## 7. ADS 指标汇总层

ADS 层用于生成 Power BI 看板直接使用的汇总指标表。

本项目只围绕最终三个页面保留 16 张 ADS 表。

---

### 7.1 经营总览 ADS 表

经营总览页面使用以下 ADS 表：

```text
ads_business_overview
ads_monthly_business_trend_stable
ads_order_status_analysis
ads_payment_type_analysis
```

各表作用如下：

| ADS 表                             | 用途                              |
| --------------------------------- | ------------------------------- |
| ads_business_overview             | 生成总 GMV、订单数、AOV、总运费、运费占比等核心 KPI |
| ads_monthly_business_trend_stable | 生成月度 GMV 趋势和月度订单数趋势             |
| ads_order_status_analysis         | 生成订单状态分布                        |
| ads_payment_type_analysis         | 生成支付方式分布                        |

---

### 7.2 物流履约 ADS 表

物流履约页面使用以下 ADS 表：

```text
ads_logistics_overview
ads_delay_review_impact
ads_delivery_days_review_analysis
ads_logistics_by_customer_state
ads_seller_logistics_analysis
```

各表作用如下：

| ADS 表                             | 用途                             |
| --------------------------------- | ------------------------------ |
| ads_logistics_overview            | 生成平均配送天数、商家发货天数、延迟送达率、差评率等 KPI |
| ads_delay_review_impact           | 分析延迟送达与未延迟送达订单在评分和差评率上的差异      |
| ads_delivery_days_review_analysis | 分析不同配送时长区间下的平均评分、差评率和好评率       |
| ads_logistics_by_customer_state   | 按客户所在州统计延迟送达率，识别高延迟地区          |
| ads_seller_logistics_analysis     | 按商家统计物流履约表现，识别高物流风险商家          |

---

### 7.3 用户运营 ADS 表

用户运营页面使用以下 ADS 表：

```text
ads_repurchase_overview
ads_user_purchase_frequency
ads_rfm_user_segment
ads_high_value_user_overview
ads_high_value_user_category
ads_at_risk_user_overview
ads_at_risk_user_priority_summary
```

各表作用如下：

| ADS 表                             | 用途                    |
| --------------------------------- | --------------------- |
| ads_repurchase_overview           | 生成用户数、复购用户数、复购率等 KPI  |
| ads_user_purchase_frequency       | 分析用户购买频次分布            |
| ads_rfm_user_segment              | 展示 RFM 用户分层规模和 GMV 贡献 |
| ads_high_value_user_overview      | 统计高价值用户数量和消费表现        |
| ads_high_value_user_category      | 分析高价值用户偏好的 Top 商品品类   |
| ads_at_risk_user_overview         | 统计流失风险用户数量和消费表现       |
| ads_at_risk_user_priority_summary | 对流失风险用户进行召回优先级划分      |

---

## 8. Power BI 看板设计

本项目最终输出三页 Power BI 可视化看板：

```text
01 经营总览
02 物流履约
03 用户运营
```

---

### 8.1 第 1 页：经营总览

经营总览页面用于观察平台整体交易规模和订单结构。

主要展示内容包括：

```text
总 GMV
订单数
客单价 AOV
总运费
运费占比
月度 GMV 趋势
月度订单数趋势
订单状态分布
支付方式分布
业务洞察
```

页面核心目标是帮助快速了解平台整体经营表现，包括交易规模、订单增长趋势和支付结构。

---

### 8.2 第 2 页：物流履约

物流履约页面用于分析物流时效对用户体验的影响。

主要展示内容包括：

```text
平均配送天数
商家发货天数
延迟送达率
差评率
延迟送达对平均评分的影响
延迟送达对差评率的影响
配送时长与用户评分关系
延迟送达率最高地区
高物流风险商家
业务洞察
```

页面核心目标是识别物流延迟是否显著影响用户评分和差评率，并定位高风险地区和高风险商家。

---

### 8.3 第 3 页：用户运营

用户运营页面用于分析用户价值分层、复购情况和流失风险。

主要展示内容包括：

```text
用户数
复购用户数
复购率
高价值用户数
流失风险用户数
用户购买频次分布
RFM 用户分层规模
RFM 用户分层 GMV 贡献
高价值用户 Top 品类
流失风险用户召回优先级
业务洞察
```

页面核心目标是识别平台用户结构、用户价值贡献和流失风险，为后续精细化运营提供支持。

---

## 9. 核心业务洞察输出

基于 SQL 指标计算和 Power BI 看板分析，项目输出以下业务洞察。

### 9.1 平台交易规模与订单结构

平台 GMV 和订单数在 2017 到 2018 年期间整体呈增长趋势，说明平台交易规模持续扩大。

支付方式以 credit_card 为主，说明信用卡支付是平台最核心的支付方式。

订单状态以 delivered 为主，说明大部分订单最终完成交付，但仍存在 canceled、unavailable、shipped 等非最终完成状态，需要关注异常订单占比。

---

### 9.2 物流延迟显著影响用户体验

延迟送达订单的平均评分明显低于未延迟送达订单，差评率明显更高。

随着总配送天数增加，订单平均评分下降，差评率上升。

这说明物流履约是影响用户体验的重要因素，平台需要重点关注高延迟地区和高延迟商家。

---

### 9.3 用户复购率较低，用户留存仍有提升空间

用户购买频次分布显示，大部分用户只购买 1 次，复购用户占比较低。

这说明平台用户整体以一次性购买为主，后续可以通过优惠券、会员体系、个性化推荐和复购召回提升用户留存。

---

### 9.4 RFM 分层可支持精细化运营

RFM 分层显示，不同用户群体在用户规模、GMV 贡献、购买频次和消费金额上存在明显差异。

高价值用户数量较少，但平均消费能力较强，适合重点维护。

流失风险用户规模较大，需要结合召回优先级进行分层运营，避免对所有用户采用同一种运营策略。

---

## 10. 项目文件说明

本项目 GitHub 仓库结构建议如下：

```text
olist-ecommerce-analysis/
│
├── README.md
├── .gitignore
│
├── sql/
│   ├── 01_create_database_and_tables.sql
│   ├── 02_dwd_cleaning_and_wide_table.sql
│   ├── 03_ads_business_overview.sql
│   ├── 04_ads_logistics_experience.sql
│   └── 05_ads_rfm_user_operation.sql
│
├── dashboard/
│   └── olist_powerbi_dashboard.pbix
│
├── images/
│   ├── 01_business_overview.png
│   ├── 02_logistics_experience.png
│   └── 03_user_operation_rfm.png
│
├── data_sample/
│   ├── ads_business_overview.csv
│   ├── ads_monthly_business_trend_stable.csv
│   ├── ads_order_status_analysis.csv
│   ├── ads_payment_type_analysis.csv
│   ├── ads_logistics_overview.csv
│   ├── ads_delay_review_impact.csv
│   ├── ads_delivery_days_review_analysis.csv
│   ├── ads_logistics_by_customer_state.csv
│   ├── ads_seller_logistics_analysis.csv
│   ├── ads_repurchase_overview.csv
│   ├── ads_user_purchase_frequency.csv
│   ├── ads_rfm_user_segment.csv
│   ├── ads_high_value_user_overview.csv
│   ├── ads_high_value_user_category.csv
│   ├── ads_at_risk_user_overview.csv
│   └── ads_at_risk_user_priority_summary.csv
│
└── docs/
    ├── metric_definition.md
    └── analysis_flow.md
```

---

## 11. 项目复现说明

如需复现本项目，可按以下步骤执行：

```text
1. 从 Kaggle 下载 Olist 原始数据集
2. 在 MySQL 中创建 olist_ecommerce 数据库
3. 导入原始 CSV 文件
4. 依次执行 sql 文件夹中的 SQL 脚本
5. 生成 DWD 清洗表和 ADS 汇总表
6. 使用 Power BI 连接 MySQL 或导出的 ADS CSV 文件
7. 根据 ADS 表构建经营总览、物流履约、用户运营三页看板
```

SQL 执行顺序如下：

```text
01_create_database_and_tables.sql
→ 02_dwd_cleaning_and_wide_table.sql
→ 03_ads_business_overview.sql
→ 04_ads_logistics_experience.sql
→ 05_ads_rfm_user_operation.sql
```

---

## 12. 项目总结

本项目完成了从原始电商多表数据到 Power BI 经营分析看板的完整数据分析流程。

项目核心价值包括：

```text
1. 使用 MySQL 完成多表关联和数据建模
2. 构建 ODS-DWD-ADS 分层分析流程
3. 基于 SQL 生成经营、物流、用户运营指标表
4. 使用 Power BI 搭建三页业务分析看板
5. 从交易规模、物流体验、用户价值三个角度输出业务洞察
```

该项目能够体现电商业务理解、SQL 数据建模能力、指标体系设计能力和 Power BI 可视化表达能力。

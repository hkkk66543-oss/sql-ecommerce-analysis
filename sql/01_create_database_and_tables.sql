-- MySQL 8.0; fresh schema bootstrap. Does not drop or truncate existing tables.
-- Import CSVs into these normalized names, not olist_*_dataset names.
-- Dates remain text for compatibility with existing 02/04/05 scripts.
-- Before importing, run scripts/prepare_olist_csv.py; see docs/sql_reproduction.md.
-- Primary keys reject duplicate business keys; do NOT use INSERT IGNORE / REPLACE.
-- Reviews and geolocation intentionally allow repeated IDs / ZIP codes.
-- No foreign keys at ODS: import order is unrestricted; validate orphans separately.
CREATE DATABASE IF NOT EXISTS olist_ecommerce
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE olist_ecommerce;

CREATE TABLE IF NOT EXISTS customers (
    customer_id CHAR(32) NOT NULL PRIMARY KEY,
    customer_unique_id CHAR(32) NOT NULL,
    customer_zip_code_prefix CHAR(5), customer_city VARCHAR(100), customer_state CHAR(2),
    KEY idx_customer_unique_id (customer_unique_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS orders (
    order_id CHAR(32) NOT NULL PRIMARY KEY, customer_id CHAR(32) NOT NULL,
    order_status VARCHAR(20) NOT NULL,
    order_purchase_timestamp VARCHAR(32), order_approved_at VARCHAR(32),
    order_delivered_carrier_date VARCHAR(32), order_delivered_customer_date VARCHAR(32),
    order_estimated_delivery_date VARCHAR(32), KEY idx_orders_customer (customer_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_items (
    order_id CHAR(32) NOT NULL, order_item_id INT NOT NULL,
    product_id CHAR(32) NOT NULL, seller_id CHAR(32) NOT NULL,
    shipping_limit_date VARCHAR(32), price DECIMAL(15,2) NOT NULL,
    freight_value DECIMAL(15,2) NOT NULL,
    PRIMARY KEY (order_id, order_item_id), KEY idx_items_product (product_id),
    KEY idx_items_seller (seller_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_payments (
    order_id CHAR(32) NOT NULL, payment_sequential INT NOT NULL,
    payment_type VARCHAR(30) NOT NULL, payment_installments INT,
    payment_value DECIMAL(15,2) NOT NULL,
    PRIMARY KEY (order_id, payment_sequential)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS order_reviews (
    review_id CHAR(32) NOT NULL, order_id CHAR(32) NOT NULL,
    review_score TINYINT, review_comment_title TEXT, review_comment_message TEXT,
    review_creation_date VARCHAR(32), review_answer_timestamp VARCHAR(32),
    KEY idx_reviews_order (order_id), KEY idx_reviews_id (review_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS products (
    product_id CHAR(32) NOT NULL PRIMARY KEY, product_category_name VARCHAR(100),
    product_name_lenght INT, product_description_lenght INT, product_photos_qty INT,
    product_weight_g INT, product_length_cm INT, product_height_cm INT, product_width_cm INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sellers (
    seller_id CHAR(32) NOT NULL PRIMARY KEY, seller_zip_code_prefix CHAR(5),
    seller_city VARCHAR(100), seller_state CHAR(2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS geolocation (
    geolocation_zip_code_prefix CHAR(5), geolocation_lat DECIMAL(12,8),
    geolocation_lng DECIMAL(12,8), geolocation_city VARCHAR(100), geolocation_state CHAR(2),
    KEY idx_geolocation_zip (geolocation_zip_code_prefix)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS category_translation (
    product_category_name VARCHAR(100) NOT NULL PRIMARY KEY,
    product_category_name_english VARCHAR(100)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

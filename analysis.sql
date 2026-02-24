/* =========================================================
   SAMSUNG GLOBAL PRODUCT SALES ANALYSIS
   Author: Juhi Kalra
   Tools: PostgreSQL
   Dataset Size: ~15,500 records
   ========================================================= */


/* =========================================================
   DATA SANITY CHECKS
   Business Question:
   Is the dataset complete and usable for analysis?
   ========================================================= */

SELECT COUNT(*) AS total_rows FROM samsung_sales_raw;

SELECT
  MIN(sale_date) AS min_sale_date,
  MAX(sale_date) AS max_sale_date
FROM samsung_sales_raw;

SELECT
  SUM(CASE WHEN revenue_usd IS NULL THEN 1 ELSE 0 END) AS null_revenue,
  SUM(CASE WHEN units_sold IS NULL THEN 1 ELSE 0 END) AS null_units,
  SUM(CASE WHEN customer_rating IS NULL THEN 1 ELSE 0 END) AS null_rating,
  SUM(CASE WHEN previous_device_os IS NULL THEN 1 ELSE 0 END) AS null_prev_os
FROM samsung_sales_raw;



/* =========================================================
   1. REVENUE BY REGION
   Business Question:
   Which regions contribute the most revenue?
   ========================================================= */

SELECT
  region,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd
FROM samsung_sales_raw
GROUP BY region
ORDER BY total_revenue_usd DESC;



/* =========================================================
   2. MONTHLY REVENUE TREND (GLOBAL)
   Business Question:
   How does revenue trend month-over-month overall?
   ========================================================= */

WITH monthly AS (
  SELECT
    DATE_TRUNC('month', sale_date)::date AS month_start,
    SUM(revenue_usd) AS revenue_usd
  FROM samsung_sales_raw
  GROUP BY month_start
)
SELECT
  month_start,
  ROUND(revenue_usd, 2) AS revenue_usd,
  ROUND(LAG(revenue_usd) OVER (ORDER BY month_start), 2) AS prev_month_revenue,
  ROUND(
    (revenue_usd - LAG(revenue_usd) OVER (ORDER BY month_start))
    / NULLIF(LAG(revenue_usd) OVER (ORDER BY month_start), 0) * 100
  , 2) AS mom_growth_pct
FROM monthly
ORDER BY month_start;



/* =========================================================
   3. TOP 10 PRODUCTS BY REVENUE
   Business Question:
   Which products generate the highest revenue?
   ========================================================= */

SELECT
  product_name,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd
FROM samsung_sales_raw
GROUP BY product_name
ORDER BY total_revenue_usd DESC
LIMIT 10;



/* =========================================================
   4. REVENUE BY SALES CHANNEL
   Business Question:
   Which sales channels generate the highest revenue and volume?
   ========================================================= */

SELECT
  sales_channel,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd,
  SUM(units_sold) AS total_units_sold,
  ROUND(AVG(discount_pct), 2) AS avg_discount_pct
FROM samsung_sales_raw
GROUP BY sales_channel
ORDER BY total_revenue_usd DESC;



/* =========================================================
   5. REVENUE BY CUSTOMER SEGMENT
   Business Question:
   Which customer segments contribute most to revenue and volume,
   and how do their average ratings compare?
   ========================================================= */

SELECT
  customer_segment,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd,
  SUM(units_sold) AS total_units_sold,
  ROUND(AVG(customer_rating), 2) AS avg_customer_rating
FROM samsung_sales_raw
GROUP BY customer_segment
ORDER BY total_revenue_usd DESC;



/* =========================================================
   6. RETURN RATE BY CATEGORY (Top return categories)
   Business Question:
   Which product categories have the highest return rates?
   ========================================================= */

WITH category_returns AS (
  SELECT
    category,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN return_status = 'Returned' THEN 1 ELSE 0 END) AS returned_orders
  FROM samsung_sales_raw
  GROUP BY category
)
SELECT
  category,
  total_orders,
  returned_orders,
  ROUND(100.0 * returned_orders / NULLIF(total_orders, 0), 2) AS return_rate_pct
FROM category_returns
ORDER BY return_rate_pct DESC;



/* =========================================================
   7. DISCOUNT IMPACT (Bucketed)
   Business Question:
   Does higher discounting significantly increase revenue and volume?
   ========================================================= */

WITH discount_buckets AS (
  SELECT
    CASE
      WHEN discount_pct IS NULL THEN 'Unknown'
      WHEN discount_pct = 0 THEN '0%'
      WHEN discount_pct <= 10 THEN '1–10%'
      WHEN discount_pct <= 20 THEN '11–20%'
      WHEN discount_pct <= 30 THEN '21–30%'
      ELSE '30%+'
    END AS discount_bucket,
    revenue_usd,
    units_sold
  FROM samsung_sales_raw
)
SELECT
  discount_bucket,
  COUNT(*) AS total_orders,
  SUM(units_sold) AS total_units_sold,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd,
  ROUND(AVG(revenue_usd), 2) AS avg_order_value_usd
FROM discount_buckets
GROUP BY discount_bucket
ORDER BY
  CASE discount_bucket
    WHEN '0%' THEN 1
    WHEN '1–10%' THEN 2
    WHEN '11–20%' THEN 3
    WHEN '21–30%' THEN 4
    WHEN '30%+' THEN 5
    ELSE 6
  END;



/* =========================================================
   8. 5G VS NON-5G PERFORMANCE
   Business Question:
   How do 5G devices compare with non-5G devices in revenue,
   volume, discounting, and ratings?
   ========================================================= */

SELECT
  COALESCE(is_5g, 'Unknown') AS is_5g_device,
  ROUND(SUM(revenue_usd), 2) AS total_revenue_usd,
  SUM(units_sold) AS total_units_sold,
  ROUND(AVG(discount_pct), 2) AS avg_discount_pct,
  ROUND(AVG(customer_rating), 2) AS avg_customer_rating
FROM samsung_sales_raw
GROUP BY COALESCE(is_5g, 'Unknown')
ORDER BY total_revenue_usd DESC;



/* =========================================================
   9. SECOND HIGHEST REVENUE PRODUCT PER CATEGORY
   Business Question:
   Which products rank second by revenue within each category?
   ========================================================= */

WITH product_revenue AS (
  SELECT
    category,
    product_name,
    SUM(revenue_usd) AS total_revenue
  FROM samsung_sales_raw
  GROUP BY category, product_name
),
ranked AS (
  SELECT
    category,
    product_name,
    total_revenue,
    DENSE_RANK() OVER (PARTITION BY category ORDER BY total_revenue DESC) AS revenue_rank
  FROM product_revenue
)
SELECT
  category,
  product_name,
  ROUND(total_revenue, 2) AS total_revenue_usd
FROM ranked
WHERE revenue_rank = 2
ORDER BY category;



/* =========================================================
   10. REGION MONTH-OVER-MONTH (MoM) REVENUE GROWTH
   Business Question:
   How is revenue trending month-over-month across regions?
   ========================================================= */

WITH regional_monthly AS (
  SELECT
    region,
    DATE_TRUNC('month', sale_date)::date AS month_start,
    SUM(revenue_usd) AS monthly_revenue
  FROM samsung_sales_raw
  GROUP BY region, month_start
)
SELECT
  region,
  month_start,
  ROUND(monthly_revenue, 2) AS revenue_usd,
  ROUND(LAG(monthly_revenue) OVER (PARTITION BY region ORDER BY month_start), 2) AS prev_month_revenue,
  ROUND(
    (monthly_revenue - LAG(monthly_revenue) OVER (PARTITION BY region ORDER BY month_start))
    / NULLIF(LAG(monthly_revenue) OVER (PARTITION BY region ORDER BY month_start), 0) * 100
  , 2) AS mom_growth_pct
FROM regional_monthly
ORDER BY region, month_start;

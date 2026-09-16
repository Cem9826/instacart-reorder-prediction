# ====================================================================
# Step 1.5 | Exploration — groups A, B, C, D
# ====================================================================
#
# A — time patterns: day, hour, day x hour, order interval distribution
# B — order sequence: reorder rate and basket size by order number
# C — basket structure: size distribution, add-to-cart position, size x reorder rate
# D — product and category: department, aisle, reorder rate normalised by popularity
#
# Group D findings sit at the end of the file as a comment block, including the
# thesis test that measured the relationship between reorder rate and purchase interval.

# GROUP A
# orders by day of week
select
  order_dow,
  count(*) total_orders
from `deneme-505002.instacart_clean.orders_prior`
group by order_dow
order by order_dow;

# orders by hour of day
select
  order_hour_of_day,
  count(*) total_orders
from `deneme-505002.instacart_clean.orders_prior`
group by order_hour_of_day
order by order_hour_of_day;

# day x hour crosstab
select
  order_dow,
  order_hour_of_day,
  count(*) total_orders
from `deneme-505002.instacart_clean.orders_prior`
group by order_dow, order_hour_of_day
order by order_dow, order_hour_of_day;


# order interval distribution (orders per day value)
select
  days_since_prior_order,
  count(*) total_orders
from `deneme-505002.instacart_clean.orders_prior`
group by days_since_prior_order
order by days_since_prior_order;


# GROUP B

# order sequence patterns: order count, average basket size, average reorder rate by order number
# question: as a user matures, does the reorder rate rise and does the basket grow or shrink?
select
  order_number,
  count(*) / count(distinct order_id) as avg_basket_size,
  avg(reordered) as avg_reordered
from `deneme-505002.instacart_clean.order_products_enriched`
group by order_number
order by order_number;

# GROUP C
# basket size distribution / reorder rate by add-to-cart position / relation between basket size and reorder rate


# basket size distribution
with basket_counts as (
  select order_id, count(*) as basket_size
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by order_id
)
select
  basket_size,
  count(*) as n_orders
from basket_counts
group by basket_size
order by basket_size;

# reorder rate by add-to-cart position
select
  add_to_cart_order,
  avg(reordered) as avg_reordered,
  count(*) as total_orders
from `deneme-505002.instacart_clean.order_products_enriched`
group by add_to_cart_order
order by add_to_cart_order;

# relation between basket size and reorder rate
with basket_stats as (
  select
    order_id,
    count(*) as basket_size,
    avg(reordered) as order_reorder_rate
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by order_id
)
select
  basket_size,
  count(*) as n_orders,
  avg(order_reorder_rate) as avg_reorder_rate
from basket_stats
group by basket_size
order by basket_size;


# GROUP D

# by department: total orders, distinct products, reorder rate
select
  department,
  count(*) as n_rows,
  count(distinct order_id) as n_orders,
  count(distinct product_id) as n_products,
  avg(reordered) as avg_reorder_rate
from `deneme-505002.instacart_clean.order_products_enriched`
group by department
order by n_rows desc;


# same three metrics by aisle
select
  aisle,
  count(*) as n_rows,
  count(distinct order_id) as n_orders,
  count(distinct product_id) as n_products,
  avg(reordered) as avg_reorder_rate
from `deneme-505002.instacart_clean.order_products_enriched`
group by aisle
order by n_rows desc;

# reorder rate normalised by popularity
with product_stats as (
  select
    product_id,
    any_value(product_name) as product_name,
    any_value(aisle) as aisle,
    any_value(department) as department,
    count(*) as n_purchases,
    avg(reordered) as reorder_rate
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by product_id
),
product_deciles as (
  select
    *,
    ntile(10) over (order by n_purchases, product_id) as popularity_decile
  from product_stats
  where n_purchases >= 500
),
decile_means as (
  select
    *,
    avg(reorder_rate) over (partition by popularity_decile) as decile_avg_reorder
  from product_deciles
)
select
  product_id,
  product_name,
  aisle,
  department,
  n_purchases,
  reorder_rate,
  popularity_decile,
  decile_avg_reorder,
  reorder_rate - decile_avg_reorder as reorder_lift
from decile_means
where popularity_decile >= 8
order by reorder_lift asc
limit 50;


# filter: at least 500 purchases (noise removal)
# THESIS TEST: "reorder rate measures consumption speed, not loyalty"
# if the thesis holds, products with a low reorder rate should have a LONG purchase interval
# filter: at least 500 purchases (noise removal)
with p as (
  select p_name, p_department, p_n_purchases, p_reorder_rate, p_avg_repeat_gap
  from `deneme-505002.instacart_features.product_features`
  where p_n_purchases >= 500 and p_avg_repeat_gap is not null
),
banded as (
  select
    *,
    ntile(10) over (order by p_reorder_rate, p_name) as reorder_decile
  from p
)
select
  reorder_decile,
  count(*) as n_products,
  min(p_reorder_rate) as min_rate,
  max(p_reorder_rate) as max_rate,
  avg(p_avg_repeat_gap) as avg_gap,
  approx_quantiles(p_avg_repeat_gap, 100)[offset(50)] as median_gap
from banded
group by reorder_decile
order by reorder_decile;

# correlation between the two columns
select
  count(*) as n_products,
  corr(p_reorder_rate, p_avg_repeat_gap) as r_rate_gap,
  corr(p_reorder_rate, log(p_avg_repeat_gap)) as r_rate_log_gap
from `deneme-505002.instacart_features.product_features`
where p_n_purchases >= 500 and p_avg_repeat_gap is not null and p_avg_repeat_gap > 0;

# ============================================================
# GROUP D — PRODUCT AND CATEGORY FINDINGS
# ============================================================

# --- by department (21 categories) ---
# high reorder: dairy eggs 67%, produce 65%, beverages 65%, bakery 63%, deli 61%
#   -> products that get consumed and run out
# low reorder: personal care 32%, pantry 35%, international 37%, household 40%
#   -> long-lasting products
# volume and loyalty are unrelated: personal care has the second widest catalogue
# with 6,563 products but the lowest reorder rate.

# --- by aisle (134 categories) ---
# the aisle level separates markedly better than the department level.
# fresh fruits 71.8% vs fresh vegetables 59.5% — both in produce, 12 points apart.
# highest: milk 78.1% / water seltzer 73.0% / fresh fruits 71.8% / eggs 70.5%


# --- reorder rate normalised by popularity ---
# method: products split into 10 deciles by purchase count (NTILE),
# each decile's own average reorder rate computed,
# each product's deviation from its own decile taken as reorder_lift.
# filters: n_purchases >= 500 and popularity_decile >= 8 (noise removal)
# product_id added to NTILE (deterministic); the 6 reference lift values did not change on rerun
# POSITIVE LIFT — mostly dairy:
#   Half And Half Ultra Pasteurized  2,921 purchases  86.2%  lift +0.316
#   Organic Homogenized Whole Milk   3,970 purchases  85.8%  lift +0.281
#   Banana                         472,565 purchases  84.4%  lift +0.225

# BANANA TEST: banana is the most popular product in the data yet it stays on the list
# after normalisation — 22 points above its own decile. The method works.

# NEGATIVE LIFT:
#   Baking Powder  4,041 purchases  9.0%  lift -0.487
#   Paprika        2,837 purchases  7.7%  lift -0.469
#   Bay Leaves     2,898 purchases  7.7%  lift -0.469
# the list is almost entirely pantry and household:
# spices, vinegars, foil, vanilla extract.

# --- CRITICAL FINDING (measured, using the corrected p_avg_repeat_gap) ---
# there is a strong NEGATIVE relationship between reorder rate and a product's
# actual purchase interval: r = -0.81 (n = 8,290 products, min 500 purchases)
#
# 10 deciles by reorder rate, average purchase interval (days):
#   decile 1  (rate 2-34%)  -> 56.0 days
#   decile 5  (rate 51-55%) -> 31.9 days
#   decile 10 (rate 70-86%) -> 21.4 days
# mean and median are nearly identical in every decile — the result is not driven by outliers.
#
# INTERPRETATION: the reordered column cannot separate two cases:
#   1) tried it, did not like it
#   2) liked it but the stock has not run out
# the interval data shows the second mechanism dominates:
# low reorder rate products are not reordered RARELY, they are reordered LATE.
#
# REORDER RATE MEASURES CONSUMPTION SPEED, NOT LOYALTY.
#
# LIMIT: this is an association measurement; the dislike effect is not fully ruled out.
# separating the two mechanisms needs product ratings or return data, which this dataset lacks.

# --- IMPLICATIONS ---
# 1) the "slippery product" definition cannot be built with this data -> scope statement
# 2) a reorder recommendation is meaningless for low reorder rate products;
#    these belong to cross-sell
# 3) product level reorder rate will be a strong feature, but it should be read as
#    "REPLENISHMENT FREQUENCY", not "loyalty"

# ====================================================================
# Step 1.3 | Data quality audit
# ====================================================================
#
# More than 15 checks: null values, out-of-range values, duplicate products within an order,
# orphan records, duplicate product names, the 'missing' category, referential integrity.
#
# Nothing required cleaning.
#
# CRITICAL FINDING — 30-day censoring:
# days_since_prior_order maxes out at 30. There are 16,976 orders at 29 and 306,137 at 30.
# Instacart wrote every interval beyond 30 days as 30. Churn cannot be defined with this data.

select
  countif(days_since_prior_order is null)  as n_null,
  min(days_since_prior_order) as min_val,
  max(days_since_prior_order) as max_val,
  avg(days_since_prior_order) as avg_val,
  approx_quantiles(days_since_prior_order, 100)[offset(50)] as median_val,
  countif(days_since_prior_order = 30) / countif(days_since_prior_order is not null) as pct_30
from `deneme-505002.instacart_raw.orders`; 


SELECT column_name, data_type
FROM `deneme-505002.instacart_raw.INFORMATION_SCHEMA.COLUMNS`
WHERE table_name = 'orders';

select * from `deneme-505002.instacart_raw.orders`limit 50;


select
  min(order_number) as min_order_number,
  max(order_number) as max_order_number,
  min(order_dow) as min_order_dow,
  max(order_dow) as max_order_dow,
  min(order_hour_of_day) as min_order_hour,
  max(order_hour_of_day) as max_order_hour,
from `deneme-505002.instacart_raw.orders`;

# orders per user
with user_orders as (
  select user_id, count(*) as n_orders
  from `deneme-505002.instacart_raw.orders`
  group by user_id
)
select
  min(n_orders) as min_orders,
  max(n_orders) as max_orders,
  avg(n_orders) as avg_orders,
  approx_quantiles(n_orders, 100)[offset(50)] as median_orders
from user_orders;


# checking the order_products table
# min 1, max 145, no gaps (starts at 1, correct)
select
  min(add_to_cart_order) as min_cart_order,
  max(add_to_cart_order) as max_cart_order
from `deneme-505002.instacart_raw.order_products_prior`;

# checking whether reordered holds any value other than 0 and 1
# 19m ones, 13m zeros (decimals omitted)
select
  reordered,
  count(*) as total_rows
from `deneme-505002.instacart_raw.order_products_prior`
group by reordered;

# same checks on order_products_train
# add_to_cart_order: min 1, max 80 — no gaps, clean
select
  min(add_to_cart_order) as min_cart_order,
  max(add_to_cart_order) as max_cart_order
from `deneme-505002.instacart_raw.order_products_train`;

# reordered: only 0 (555,793) and 1 (828,824) — no invalid values, reorder rate 59.9%
select
  reordered,
  count(*) as total_rows
from `deneme-505002.instacart_raw.order_products_train`
group by reordered;


# distribution of items per order — train
# min 1, max 145 (prior) / 80 (train) — no outliers, right-skewed distribution
with basket_size as (
  select order_id, count(*) as n_products
  from `deneme-505002.instacart_raw.order_products_train`
  group by order_id
)
select
  min(n_products) as min_order,
  max(n_products) as max_order,
  avg(n_products) as avg_order,
  approx_quantiles(n_products, 100)[offset(50)] as median_products
from basket_size;

# distribution of items per order — prior
# basket size: prior avg 10.09 / median 8 — train avg 10.55 / median 9
with basket_size as (
  select order_id, count(*) as n_products
  from `deneme-505002.instacart_raw.order_products_prior`
  group by order_id
)
select
  min(n_products) as min_order,
  max(n_products) as max_order,
  avg(n_products) as avg_order,
  approx_quantiles(n_products, 100)[offset(50)] as median_products
from basket_size;
# the two sets are similar; train does not behave systematically differently




# does the same product repeat within a single order — it should not; if it does, a cleaning decision is needed
select
  order_id,
  product_id,
  count(*) as total_rows
from `deneme-505002.instacart_raw.order_products_train`
group by order_id, product_id
having count(*) > 1;

# same check on prior
select
  order_id,
  product_id,
  count(*) as total_rows
from `deneme-505002.instacart_raw.order_products_prior`
group by order_id, product_id
having count(*) > 1;

# order_id + product_id duplicates: 0 rows in prior, 0 rows in train — no duplicates, no cleaning needed
# note: the dataset has no quantity column, "how many were bought" is unavailable (goes to scope statement)



# empty product names / same product name under multiple ids / products tied to the 'missing' category
select
  count(*) as total_rows,
  countif(product_name is null) as null_names,
  countif(trim(product_name) = '') as empty_names,
  countif(product_name is null or trim(product_name) = '') as total_invalid
from `deneme-505002.instacart_raw.products`;


# checking whether the same product name is registered under more than one id
select
  product_name,
  count(distinct product_id) as unique_product
from `deneme-505002.instacart_raw.products`
group by product_name
having count(distinct product_id) > 1;

# locating the id of the 'missing' aisle -> aisle_id = 100
select *
from `deneme-505002.instacart_raw.aisles`
where aisle = 'missing';

# locating the id of the 'missing' department -> department_id = 21
select *
from `deneme-505002.instacart_raw.departments`
where department = 'missing';

# product count and share tied to the 'missing' category
select
  count(*) as total_products,
  countif(aisle_id = 100) as missing_aisle_products,
  countif(aisle_id = 100) / count(*) as missing_aisle_ratio,
  countif(department_id = 21) as missing_department_products,
  countif(department_id = 21) / count(*) as missing_department_ratio
from `deneme-505002.instacart_raw.products`;

# verifying whether 'missing' in both columns points to the same products
# both_missing 1258, none missing in only one column — uncategorised products are flagged in both columns
select
  countif(aisle_id = 100 and department_id = 21) as both_missing,
  countif(aisle_id = 100 and department_id != 21) as only_aisle_missing,
  countif(aisle_id != 100 and department_id = 21) as only_department_missing 
from `deneme-505002.instacart_raw.products`;


# referential integrity checks

# how many prior order ids have no match in the orders table
select count(*) as orphan_rows
from `deneme-505002.instacart_raw.order_products_prior` op
left join `deneme-505002.instacart_raw.orders` o
  on op.order_id = o.order_id
where o.order_id is null;

select count(*) as orphan_rows
from `deneme-505002.instacart_raw.order_products_train` op
left join `deneme-505002.instacart_raw.orders` o
  on op.order_id = o.order_id
where o.order_id is null;

# any product in order_products with no match in the products table
select count(*) as orphan_rows
from `deneme-505002.instacart_raw.order_products_prior` op
left join `deneme-505002.instacart_raw.products` p
  on op.product_id = p.product_id
where p.product_id is null;


select count(*) as orphan_rows
from `deneme-505002.instacart_raw.order_products_train` op
left join `deneme-505002.instacart_raw.products` p
  on op.product_id = p.product_id
where p.product_id is null;

# any id in products with no match in aisles or departments
select count(*) as orphan_rows
from `deneme-505002.instacart_raw.products` p
left join `deneme-505002.instacart_raw.aisles` a
  on p.aisle_id = a.aisle_id
where a.aisle_id is null;

select count(*) as orphan_rows
from `deneme-505002.instacart_raw.products` p
left join `deneme-505002.instacart_raw.departments` d
  on p.department_id = d.department_id
where d.department_id is null;

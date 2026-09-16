# ====================================================================
# Step 1.6 | Feature tables
# ====================================================================
#
# GOLDEN RULE: every feature is computed from prior orders only.
# The train order is the target variable and is never used in feature generation.
#
# user_features          131,209 rows
# product_features        49,677 rows
# aisle_features             134 rows
# department_features         21 rows
# user_product_features  8,474,661 rows
#
# The single exception is u_days_since_last_order, which comes from the train row but is
# not leakage: how many days have passed when a user places an order is known at prediction time.
#
# This file carries three revisions — the product/aisle/department purchase interval fix,
# the category second-purchase rate fix and NTILE determinism. Rationale is in the comments.

# Step 1.6 — feature tables

# Table 1 — user features (FROM PRIOR ORDERS ONLY)
create or replace table `deneme-505002.instacart_features.user_features` as

with base as (
  select
    user_id,
    count(distinct order_id) as u_n_orders,
    count(*) as u_total_items,
    count(distinct product_id) as u_n_products,
    count(distinct aisle) as u_n_aisles,
    count(distinct department) as u_n_departments,
    avg(reordered) as u_reorder_rate
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id
),

basket as (
  select
    user_id,
    avg(basket_size) as u_avg_basket,
    stddev(basket_size) as u_sd_basket
  from (
    select user_id, order_id, count(*) as basket_size
    from `deneme-505002.instacart_clean.order_products_enriched`
    group by user_id, order_id
  )
  group by user_id
),

rhythm as (
  select
    user_id,
    avg(days_since_prior_order) as u_avg_gap,
    stddev(days_since_prior_order) as u_sd_gap,
    avg(sin(2 * acos(-1) * order_hour_of_day / 24)) as u_hour_sin,
    avg(cos(2 * acos(-1) * order_hour_of_day / 24)) as u_hour_cos
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
),

dow_rank as (
  select
    user_id,
    order_dow,
    row_number() over (partition by user_id order by count(*) desc, order_dow) as rn
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id, order_dow
),

top_dow as (
  select user_id, order_dow as u_top_dow
  from dow_rank
  where rn = 1
),

train_gap as (
  select
    user_id,
    days_since_prior_order as u_days_since_last_order
  from `deneme-505002.instacart_clean.orders_train`
)

select
  b.user_id,
  b.u_n_orders,
  b.u_total_items,
  b.u_n_products,
  b.u_n_aisles,
  b.u_n_departments,
  bk.u_avg_basket,
  bk.u_sd_basket,
  r.u_avg_gap,
  r.u_sd_gap,
  b.u_reorder_rate,
  r.u_hour_sin,
  r.u_hour_cos,
  d.u_top_dow,
  t.u_days_since_last_order
from base b
join basket bk on b.user_id = bk.user_id
join rhythm r on b.user_id = r.user_id
join top_dow d on b.user_id = d.user_id
join `deneme-505002.instacart_clean.study_users` su on b.user_id = su.user_id
left join train_gap t on b.user_id = t.user_id;

select
  count(*) as n_rows,
  countif(u_hour_sin is null) as null_sin,
  min(u_hour_sin) as min_sin,
  max(u_hour_cos) as max_cos
from `deneme-505002.instacart_features.user_features`;

select count(*) from `deneme-505002.instacart_features.user_features`;


select
  countif(u_sd_basket is null) as null_sd_basket,
  countif(u_avg_gap is null) as null_avg_gap,
  countif(u_sd_gap is null) as null_sd_gap,
  countif(u_days_since_last_order is null) as null_train_gap,
  min(u_n_orders) as min_orders,
  max(u_n_orders) as max_orders,
  avg(u_reorder_rate) as avg_reorder,
  avg(u_avg_basket) as avg_basket,
  avg(u_n_aisles) as avg_aisles
from `deneme-505002.instacart_features.user_features`;



# Step 1.6 fix — Stage 1: order timeline (all users, prior only)
# cum_days: cumulative days from the user's first order up to this order
# this is a lower bound because of the 30-day censoring
create or replace view `deneme-505002.instacart_clean.order_timeline` as
select
  user_id,
  order_id,
  order_number,
  days_since_prior_order,
  sum(coalesce(days_since_prior_order, 0)) over (
    partition by user_id
    order by order_number
    rows between unbounded preceding and current row
  ) as cum_days
from `deneme-505002.instacart_clean.orders_prior`;

# expected: n_rows 3,214,874 / n_users 206,209 / bad_first 0 / negative_cum 0
select
  count(*) as n_rows,
  count(distinct user_id) as n_users,
  countif(order_number = 1 and cum_days != 0) as bad_first,
  countif(cum_days < 0) as negative_cum
from `deneme-505002.instacart_clean.order_timeline`;



# backup before Stage 2 — kept to compare against the old p_avg_repeat_gap
create table `deneme-505002.instacart_features.product_features_v1` as
select * from `deneme-505002.instacart_features.product_features`;






# Table 2 — product features (FROM PRIOR ORDERS ONLY)
create or replace table `deneme-505002.instacart_features.product_features` as

with base as (
  select
    product_id,
    any_value(product_name) as p_name,
    any_value(aisle_id) as p_aisle_id,
    any_value(aisle) as p_aisle,
    any_value(department_id) as p_department_id,
    any_value(department) as p_department,
    count(*) as p_n_purchases,
    count(distinct user_id) as p_n_users,
    avg(reordered) as p_reorder_rate,
    avg(add_to_cart_order) as p_avg_cart_position
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by product_id
),

# share of first-time buyers who bought a second time
second_purchase as (
  select
    product_id,
    countif(times_bought >= 2) / count(*) as p_second_purchase_rate,
    avg(times_bought) as p_avg_times_per_user
  from (
    select product_id, user_id, count(*) as times_bought
    from `deneme-505002.instacart_clean.order_products_enriched`
    group by product_id, user_id
  )
  group by product_id
),

# actual product level repeat purchase interval (days)
# per (user, product) pair: days between first and last purchase, purchases - 1 intervals
# all intervals weighted equally at product level: sum(day span) / sum(purchases - 1)
# frequent buyers produce more intervals, so they carry more weight
# this is a lower bound because of the 30-day censoring
repeat_rhythm as (
  select
    product_id,
    sum(span_days) / sum(n_purchases - 1) as p_avg_repeat_gap
  from (
    select
      e.user_id,
      e.product_id,
      count(*) as n_purchases,
      max(t.cum_days) - min(t.cum_days) as span_days
    from `deneme-505002.instacart_clean.order_products_enriched` e
    join `deneme-505002.instacart_clean.order_timeline` t
      on e.order_id = t.order_id
    group by e.user_id, e.product_id
    having count(*) >= 2
  )
  group by product_id
),

# product_id as the second sort key: decile assignment is deterministic for products with equal sales
deciles as (
  select
    *,
    ntile(10) over (order by p_n_purchases, product_id) as p_popularity_decile
  from base
),

normalized as (
  select
    *,
    avg(p_reorder_rate) over (partition by p_popularity_decile) as p_decile_avg_reorder
  from deciles
)

select
  n.product_id,
  n.p_name,
  n.p_aisle_id,
  n.p_aisle,
  n.p_department_id,
  n.p_department,
  n.p_n_purchases,
  n.p_n_users,
  n.p_reorder_rate,
  sp.p_second_purchase_rate,
  sp.p_avg_times_per_user,
  n.p_avg_cart_position,
  rr.p_avg_repeat_gap,
  n.p_popularity_decile,
  n.p_decile_avg_reorder,
  n.p_reorder_rate - n.p_decile_avg_reorder as p_reorder_lift
from normalized n
join second_purchase sp on n.product_id = sp.product_id
left join repeat_rhythm rr on n.product_id = rr.product_id;

select table_name, creation_time
from `deneme-505002.instacart_features.INFORMATION_SCHEMA.TABLES`
where table_name in ('product_features', 'product_features_v1');




select
  count(*) as n_rows,
  count(distinct product_id) as n_products,
  countif(p_avg_repeat_gap is null) as null_repeat_gap
from `deneme-505002.instacart_features.product_features`;



# Stage 2 validation — old (order interval) vs new (product purchase interval)
select
  n.p_name,
  n.p_n_purchases,
  n.p_reorder_rate,
  o.p_avg_repeat_gap as old_gap,
  n.p_avg_repeat_gap as new_gap
from `deneme-505002.instacart_features.product_features` n
join `deneme-505002.instacart_features.product_features_v1` o
  on n.product_id = o.product_id
where n.p_name in ('Banana', 'Organic Homogenized Whole Milk', 'Baking Powder', 'Bay Leaves')
order by n.p_reorder_rate desc;

# overall distribution comparison
select
  min(o.p_avg_repeat_gap) as old_min,
  max(o.p_avg_repeat_gap) as old_max,
  avg(o.p_avg_repeat_gap) as old_avg,
  min(n.p_avg_repeat_gap) as new_min,
  max(n.p_avg_repeat_gap) as new_max,
  avg(n.p_avg_repeat_gap) as new_avg,
  corr(o.p_avg_repeat_gap, n.p_avg_repeat_gap) as r_old_new
from `deneme-505002.instacart_features.product_features` n
join `deneme-505002.instacart_features.product_features_v1` o
  on n.product_id = o.product_id;

# Stage 2 validation — are the columns other than repeat gap unchanged
select
  count(*) as n_products,
  countif(abs(n.p_reorder_rate - o.p_reorder_rate) > 1e-9) as reorder_changed,
  countif(abs(n.p_second_purchase_rate - o.p_second_purchase_rate) > 1e-9) as second_changed,
  countif(n.p_popularity_decile != o.p_popularity_decile) as decile_changed,
  countif(abs(n.p_reorder_lift - o.p_reorder_lift) > 1e-9) as lift_changed
from `deneme-505002.instacart_features.product_features` n
join `deneme-505002.instacart_features.product_features_v1` o
  on n.product_id = o.product_id;

# NTILE fix validation — does the table match the decile recomputed with the same rule
with recomputed as (
  select
    product_id,
    ntile(10) over (order by p_n_purchases, product_id) as decile_check
  from `deneme-505002.instacart_features.product_features`
)
select countif(pf.p_popularity_decile != r.decile_check) as mismatch
from `deneme-505002.instacart_features.product_features` pf
join recomputed r using (product_id);

select table_name, creation_time
from `deneme-505002.instacart_features.INFORMATION_SCHEMA.TABLES`
where table_name = 'product_features';


create table `deneme-505002.instacart_features.aisle_features_v1` as
select * from `deneme-505002.instacart_features.aisle_features`;

create table `deneme-505002.instacart_features.department_features_v1` as
select * from `deneme-505002.instacart_features.department_features`;

# Table 3a — aisle features (FROM PRIOR ORDERS ONLY)
# times_bought = count(distinct order_id): several products from the same aisle in one order count as one purchase
# a_avg_repeat_gap: same method as product_features, from the order_timeline view
create or replace table `deneme-505002.instacart_features.aisle_features` as

with base as (
  select
    aisle_id,
    any_value(aisle) as a_name,
    any_value(department_id) as a_department_id,
    count(*) as a_n_purchases,
    count(distinct user_id) as a_n_users,
    count(distinct product_id) as a_n_products,
    avg(reordered) as a_reorder_rate,
    avg(add_to_cart_order) as a_avg_cart_position
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by aisle_id
),

# per (user, aisle): in how many distinct orders it appeared, days between first and last purchase
user_aisle as (
  select
    e.aisle_id,
    e.user_id,
    count(distinct e.order_id) as n_orders,
    max(t.cum_days) - min(t.cum_days) as span_days
  from `deneme-505002.instacart_clean.order_products_enriched` e
  join `deneme-505002.instacart_clean.order_timeline` t
    on e.order_id = t.order_id
  group by e.aisle_id, e.user_id
),

second_purchase as (
  select
    aisle_id,
    countif(n_orders >= 2) / count(*) as a_second_purchase_rate,
    avg(n_orders) as a_avg_times_per_user
  from user_aisle
  group by aisle_id
),

repeat_rhythm as (
  select
    aisle_id,
    sum(span_days) / sum(n_orders - 1) as a_avg_repeat_gap
  from user_aisle
  where n_orders >= 2
  group by aisle_id
)

select
  b.aisle_id,
  b.a_name,
  b.a_department_id,
  b.a_n_purchases,
  b.a_n_users,
  b.a_n_products,
  b.a_reorder_rate,
  sp.a_second_purchase_rate,
  sp.a_avg_times_per_user,
  b.a_avg_cart_position,
  rr.a_avg_repeat_gap,
  b.a_n_purchases / b.a_n_users as a_purchases_per_user
from base b
join second_purchase sp on b.aisle_id = sp.aisle_id
left join repeat_rhythm rr on b.aisle_id = rr.aisle_id;


# Table 3b — department features (FROM PRIOR ORDERS ONLY)
# times_bought = count(distinct order_id): several products from the same department in one order count as one purchase
# d_avg_repeat_gap: same method as product_features, from the order_timeline view
create or replace table `deneme-505002.instacart_features.department_features` as

with base as (
  select
    department_id,
    any_value(department) as d_name,
    count(*) as d_n_purchases,
    count(distinct user_id) as d_n_users,
    count(distinct product_id) as d_n_products,
    count(distinct aisle_id) as d_n_aisles,
    avg(reordered) as d_reorder_rate,
    avg(add_to_cart_order) as d_avg_cart_position
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by department_id
),

# per (user, department): in how many distinct orders it appeared, days between first and last purchase
user_dept as (
  select
    e.department_id,
    e.user_id,
    count(distinct e.order_id) as n_orders,
    max(t.cum_days) - min(t.cum_days) as span_days
  from `deneme-505002.instacart_clean.order_products_enriched` e
  join `deneme-505002.instacart_clean.order_timeline` t
    on e.order_id = t.order_id
  group by e.department_id, e.user_id
),

second_purchase as (
  select
    department_id,
    countif(n_orders >= 2) / count(*) as d_second_purchase_rate,
    avg(n_orders) as d_avg_times_per_user
  from user_dept
  group by department_id
),

repeat_rhythm as (
  select
    department_id,
    sum(span_days) / sum(n_orders - 1) as d_avg_repeat_gap
  from user_dept
  where n_orders >= 2
  group by department_id
)

select
  b.department_id,
  b.d_name,
  b.d_n_purchases,
  b.d_n_users,
  b.d_n_products,
  b.d_n_aisles,
  b.d_reorder_rate,
  sp.d_second_purchase_rate,
  sp.d_avg_times_per_user,
  b.d_avg_cart_position,
  rr.d_avg_repeat_gap,
  b.d_n_purchases / b.d_n_users as d_purchases_per_user
from base b
join second_purchase sp on b.department_id = sp.department_id
left join repeat_rhythm rr on b.department_id = rr.department_id;

# Stage 3 validation — old vs new
# expected: n_rows 134 / 21, reorder_changed 0, ppu_changed 0,
# second_increased 0, times_increased 0, old_times_eq_ppu = n_rows (the old column was a copy)
select
  'aisle' as level,
  count(*) as n_rows,
  countif(abs(n.a_reorder_rate - o.a_reorder_rate) > 1e-9) as reorder_changed,
  countif(abs(n.a_purchases_per_user - o.a_purchases_per_user) > 1e-9) as ppu_changed,
  countif(n.a_second_purchase_rate > o.a_second_purchase_rate + 1e-9) as second_increased,
  countif(n.a_avg_times_per_user > o.a_avg_times_per_user + 1e-9) as times_increased,
  countif(abs(o.a_avg_times_per_user - o.a_purchases_per_user) < 1e-9) as old_times_eq_ppu,
  countif(n.a_avg_repeat_gap is null) as null_gap,
  avg(o.a_avg_repeat_gap) as old_gap_avg,
  avg(n.a_avg_repeat_gap) as new_gap_avg
from `deneme-505002.instacart_features.aisle_features` n
join `deneme-505002.instacart_features.aisle_features_v1` o using (aisle_id)

union all

select
  'department',
  count(*),
  countif(abs(n.d_reorder_rate - o.d_reorder_rate) > 1e-9),
  countif(abs(n.d_purchases_per_user - o.d_purchases_per_user) > 1e-9),
  countif(n.d_second_purchase_rate > o.d_second_purchase_rate + 1e-9),
  countif(n.d_avg_times_per_user > o.d_avg_times_per_user + 1e-9),
  countif(abs(o.d_avg_times_per_user - o.d_purchases_per_user) < 1e-9),
  countif(n.d_avg_repeat_gap is null),
  avg(o.d_avg_repeat_gap),
  avg(n.d_avg_repeat_gap)
from `deneme-505002.instacart_features.department_features` n
join `deneme-505002.instacart_features.department_features_v1` o using (department_id);

# sample aisles — old vs new
select
  n.a_name,
  o.a_second_purchase_rate as old_second,
  n.a_second_purchase_rate as new_second,
  o.a_avg_repeat_gap as old_gap,
  n.a_avg_repeat_gap as new_gap
from `deneme-505002.instacart_features.aisle_features` n
join `deneme-505002.instacart_features.aisle_features_v1` o using (aisle_id)
where n.a_name in ('milk', 'fresh fruits', 'spices seasonings', 'baking ingredients')
order by n.a_avg_repeat_gap;






select
  (select count(*) from `deneme-505002.instacart_features.aisle_features`) as n_aisles,
  (select count(*) from `deneme-505002.instacart_features.department_features`) as n_departments;




# Table 4 — user-product features (FROM PRIOR ORDERS ONLY)
create or replace table `deneme-505002.instacart_features.user_product_features` as

# cumulative day position of each order on the user's timeline
with order_timeline as (
  select
    user_id,
    order_id,
    order_number,
    sum(coalesce(days_since_prior_order, 0)) over (
      partition by user_id order by order_number
      rows between unbounded preceding and current row
    ) as cum_days
  from `deneme-505002.instacart_clean.orders_prior`
),

user_end as (
  select
    user_id,
    max(order_number) as last_prior_order,
    max(cum_days) as total_prior_days
  from order_timeline
  group by user_id
),

# attach the timeline to the product lines
enriched as (
  select
    e.user_id,
    e.product_id,
    e.order_number,
    e.add_to_cart_order,
    t.cum_days
  from `deneme-505002.instacart_clean.order_products_enriched` e
  join order_timeline t on e.order_id = t.order_id
),

base as (
  select
    user_id,
    product_id,
    count(*) as up_n_purchases,
    min(order_number) as up_first_order,
    max(order_number) as up_last_order,
    avg(add_to_cart_order) as up_avg_cart_position,
    max(cum_days) as up_last_cum_day,
    # personal purchase interval: days between first and last purchase / (purchases - 1)
    case
      when count(*) > 1
      then (max(cum_days) - min(cum_days)) / (count(*) - 1)
      else null
    end as up_avg_repeat_gap
  from enriched
  group by user_id, product_id
),

# purchase count within the last 5 orders
recent as (
  select
    e.user_id,
    e.product_id,
    count(*) as up_last5_purchases
  from enriched e
  join user_end ue on e.user_id = ue.user_id
  where e.order_number > ue.last_prior_order - 5
  group by e.user_id, e.product_id
)

select
  b.user_id,
  b.product_id,
  b.up_n_purchases,
  b.up_first_order,
  b.up_last_order,
  # how many orders have passed since the last purchase
  ue.last_prior_order - b.up_last_order as up_orders_since_last,
  # how many days have passed since the last purchase (train order included)
  ue.total_prior_days - b.up_last_cum_day
    + coalesce(uf.u_days_since_last_order, 0) as up_days_since_last,
  # in what share of the orders after the first purchase it was bought again
  b.up_n_purchases / (ue.last_prior_order - b.up_first_order + 1) as up_order_rate,
  coalesce(r.up_last5_purchases, 0) as up_last5_purchases,
  b.up_avg_cart_position,
  b.up_avg_repeat_gap,
  # position relative to the user's overall reorder rate
  b.up_n_purchases / ue.last_prior_order as up_share_of_orders,
  b.up_n_purchases / ue.last_prior_order - uf.u_reorder_rate as up_relative_to_user
from base b
join user_end ue on b.user_id = ue.user_id
join `deneme-505002.instacart_features.user_features` uf on b.user_id = uf.user_id
left join recent r on b.user_id = r.user_id and b.product_id = r.product_id;



select
  count(*) as n_rows,
  count(distinct user_id) as n_users,
  countif(up_orders_since_last < 0) as negative_orders_since,
  countif(up_days_since_last < 0) as negative_days_since,
  countif(up_order_rate > 1) as rate_over_one,
  avg(up_n_purchases) as avg_purchases,
  avg(up_last5_purchases) as avg_last5,
  max(up_orders_since_last) as max_orders_since
from `deneme-505002.instacart_features.user_product_features`;



# ============================================================
# STEP 1.6 — FEATURE TABLES
# GOLDEN RULE: every feature is computed FROM PRIOR ORDERS ONLY.
# the train order is the target variable and is never used in feature generation.
# ============================================================

# --- TABLE 1: user_features ---
# source: order_products_enriched (prior only) + orders_prior
# joined with study_users -> only users who have a train order
# row count: 131,209  (matches the expected value)
#
# row_number() is used for u_top_dow; order_dow added as the second sort key
# so that ties resolve deterministically.
#
# REVISION: u_avg_hour -> u_hour_sin, u_hour_cos
#   hour is cyclical: the arithmetic mean of 23 and 1 comes out as 12
#   the old version was product-line based (large baskets dominated),
#   the new version is order based (orders_prior)
#   validation: 131,209 rows, no NULLs, values between -1 and 1

# EXCEPTION: u_days_since_last_order comes from the train row.
# NOT leakage — how many days have passed when the user places an order
# is already known at prediction time. The rationale goes into the README.
#
# VALIDATION RESULT:
#   no NULLs (sd_basket, avg_gap, sd_gap, train_gap all 0)
#   min_orders = 3, max_orders = 99
#   avg_reorder = 0.432 / avg_basket = 9.95 / avg_aisles = 27.8
#
# NOTE — why min_orders is 3:
# every user in the dataset has at least 4 orders, but this table counts
# PRIOR orders only. For a user with 4 orders, 3 are prior and 1 is train.
# so a minimum of 3 is proof that the features are not fed from train.
#
#
# NOTE — why avg_reorder is 43.2% (it was 59% on an order basis):
# here every USER carries equal weight; there every PRODUCT LINE did.
# users with many orders have a high reorder rate, so they pulled the
# line-level average up. Both are correct, they answer different questions.
# state which one is being used when reporting.

# --- TABLE 2: product_features ---
# source: order_products_enriched (prior only)
# row count: 49,677
#
# NOTE — why not 49,688:
# the catalogue holds 49,688 products but 11 of them never appear in prior
# orders. Those 11 are absent from this table.
# check this when building the candidate set in Phase 2.
#
# p_second_purchase_rate: share of buyers who bought the product >= 2 times
# p_avg_repeat_gap: the product's actual repeat purchase interval (days)
#   sum(days between first and last purchase) / sum(purchases - 1), from the order_timeline view
#   OLD BROKEN VERSION: avg(days_since_prior_order) where reordered = 1
#   -> that measured the user's ORDER interval, not the product interval
#   validation: Baking Powder old 7.6 / new 83.1 — Banana old 10.5 / new 18.6
#   old-new correlation 0.20 / new max 356 (the old one was censored at 30)
#   still a lower bound because of the 30-day censoring
# p_reorder_lift: deviation from the mean of its own popularity decile
#
# p_popularity_decile: product_id added to NTILE as the second sort key
#   in the old version products with equal sales fell into different deciles on each run
#   evidence: 1,198 products changed decile between two runs; after the fix mismatch = 0
#
# NOTE — why there is no decile filter here:
# the exploration query in 1.5 had an n_purchases >= 500 filter.
# there is NONE here, because this is a feature table — products cannot be dropped.
# consequence: p_reorder_lift will be noisy for low-selling products.
# it must be used TOGETHER with p_n_purchases in the model.
#
# NOTE — 4,372 NULLs (p_avg_repeat_gap):
# these products were never reordered in prior (8.8% of the total).
# expected, not an error.
# IMPUTATION DECISION: filling with zero would be WRONG —
# zero days means "bought again the same day".
# either a separate flag column will be added or the median will be used.
# the decision goes into the README.

# --- TABLE 3a: aisle_features / 3b: department_features ---
# source: order_products_enriched (prior only)
# row count: 134 aisles / 21 departments  (matches the expected values)
#
# PURPOSE: generalisation for rare products. For a product with little data the
# model cannot rely on its own statistics and can fall back on the category average.
#
# NOTE — why two separate tables:
# aisle and department are different granularities. Kept apart so the model can
# join both to the product. The same metrics as product_features were produced
# so that they stay comparable.
#
# NOTE — why the popularity decile (NTILE) was NOT added:
# it worked at product level because there were 49,677 products.
# splitting 134 aisles into 10 deciles leaves 13 categories per decile and the
# normalisation becomes meaningless. For 21 departments it makes no sense at all.
#
# a_purchases_per_user / d_purchases_per_user:
# category intensity — how many times a user buys from that category on average.
#
# FIX (Stage 3):
#   times_bought: count(*) -> count(distinct order_id)
#   the old version counted several products from the same category in one order as separate purchases
#   evidence: the old avg_times_per_user equalled purchases_per_user in 134/134 aisles and 21/21 departments
#   second_purchase example: spices seasonings 0.568 -> 0.474 / milk 0.775 -> 0.766
#   avg_repeat_gap: same method as product_features (order_timeline)
#   example: spices seasonings 9.2 -> 48.4 days / fresh fruits 9.7 -> 14.5 days
#   averages: aisle 10.4 -> 34.1 / department 10.2 -> 23.2
#   the aisle_features CREATE statement was added to this file with this revision

# --- TABLE 4: user_product_features ---
# source: order_products_enriched (prior only) + orders_prior + user_features
# row count: 8,474,661 / 131,209 users
# 64.6 products per user on average — matches u_n_products (64.5) in user_features
#
# THE MOST IMPORTANT TABLE. Most of the model's power comes from here.
#
# order_timeline CTE: the cumulative day position of each order on the user's
# timeline. The per-user cumulative sum of days_since_prior_order.
# the first order is NULL, hence coalesce(...,0).
#
# up_days_since_last is built from two parts:
#   (end of prior - last purchase day) + days up to the train order
# the second part comes from user_features.u_days_since_last_order —
# the legitimate exception defined in STEP 1.6. Known at prediction time.
#
# up_order_rate denominator: last_prior_order - first_purchase_order + 1
# so for a product first bought at order 5 by a user with 20 orders, the denominator is 16.
# it answers "in what share of the orders where it could have been bought was it bought".
#
# up_avg_repeat_gap: (last purchase day - first purchase day) / (purchases - 1)
# NULL for pairs bought only once — correct behaviour, zero would be wrong.
#
# VALIDATION RESULT:
#   negative_orders_since = 0, negative_days_since = 0, rate_over_one = 0
#   avg_purchases = 2.44 / avg_last5 = 0.74 / max_orders_since = 98
#
# EXPECTATION (to be tested in Phase 2):
# up_orders_since_last and up_last5_purchases should appear near the top of the
# feature importance list. If they do not, something is wrong in feature generation.




# ceiling imposed by candidate generation: how many train products appear in prior
with train_items as (
  select o.user_id, t.product_id
  from `deneme-505002.instacart_raw.order_products_train` t
  join `deneme-505002.instacart_clean.orders_train` o on t.order_id = o.order_id
),
prior_items as (
  select distinct user_id, product_id
  from `deneme-505002.instacart_clean.order_products_enriched`
)
select
  count(*) as n_train_items,
  countif(p.product_id is not null) as n_reachable,
  countif(p.product_id is null) as n_unreachable,
  countif(p.product_id is not null) / count(*) as max_recall
from train_items ti
left join prior_items p
  on ti.user_id = p.user_id and ti.product_id = p.product_id;
  
# F1 CEILING — computed per user (because the metric is the mean of per-user F1)
# a perfect model predicts every reachable product and nothing else
#   precision = 1, recall = n_reach / n_train
#   F1 = 2 * n_reach / (n_reach + n_train)
# for a user with n_reach = 0 (no product in the train basket appears in prior) the ceiling is 0
with train_basket as (
  select o.user_id, count(*) as n_train
  from `deneme-505002.instacart_raw.order_products_train` t
  join `deneme-505002.instacart_clean.orders_train` o on t.order_id = o.order_id
  group by o.user_id
),
reachable as (
  select user_id, sum(target) as n_reach
  from `deneme-505002.instacart_features.training_set`
  group by user_id
),
per_user as (
  select
    b.user_id,
    b.n_train,
    r.n_reach,
    2 * r.n_reach / (r.n_reach + b.n_train) as f1_ceiling
  from train_basket b
  join reachable r on b.user_id = r.user_id
)
select
  count(*) as n_users,
  sum(n_train) as total_train_items,
  sum(n_reach) as total_reachable,
  avg(f1_ceiling) as macro_f1_ceiling,
  approx_quantiles(f1_ceiling, 100)[offset(50)] as median_f1_ceiling,
  2 * sum(n_reach) / (sum(n_reach) + sum(n_train)) as micro_f1_ceiling,
  countif(n_reach = 0) as users_no_reachable,
  countif(n_reach = 0) / count(*) as pct_no_reachable
from per_user;

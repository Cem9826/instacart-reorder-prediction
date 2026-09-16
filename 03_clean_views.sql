# ====================================================================
# Step 1.4 | instacart_clean views
# ====================================================================
#
# Four views. No physical tables are copied — that would mean redundant storage and sync work.
#
# orders_prior              eval_set = 'prior'
# orders_train              eval_set = 'train'
# study_users               users who have a train order
# order_products_enriched   prior product lines + orders + products + aisles + departments
#
# The last view is the important one: 32,434,489 rows, no rows lost in the joins.
# Every query from this point on reads from this single view.

# Step 1.4 — creating the instacart_clean views



# prior orders
create or replace view `deneme-505002.instacart_clean.orders_prior` as
select * from `deneme-505002.instacart_raw.orders`
where eval_set = 'prior';

# train orders
create or replace view `deneme-505002.instacart_clean.orders_train` as
select * from `deneme-505002.instacart_raw.orders`
where eval_set = 'train';

# users who have a train order
create or replace view `deneme-505002.instacart_clean.study_users` as
select distinct user_id
from `deneme-505002.instacart_raw.orders`
where eval_set = 'train';

# prior order lines + user info + order sequence + time + aisle + department
create or replace view `deneme-505002.instacart_clean.order_products_enriched` as
select
  op.order_id,
  op.product_id,
  op.add_to_cart_order,
  op.reordered,
  o.user_id,
  o.order_number,
  o.order_dow,
  o.order_hour_of_day,
  o.days_since_prior_order,
  p.product_name,
  p.aisle_id,
  a.aisle,
  p.department_id,
  d.department
from `deneme-505002.instacart_raw.order_products_prior` op
join `deneme-505002.instacart_raw.orders` o on op.order_id = o.order_id
join `deneme-505002.instacart_raw.products` p on op.product_id = p.product_id
join `deneme-505002.instacart_raw.aisles` a on p.aisle_id = a.aisle_id
join `deneme-505002.instacart_raw.departments` d on p.department_id = d.department_id;


select count(*) from `deneme-505002.instacart_clean.order_products_enriched`;


select * from `deneme-505002.instacart_clean.order_products_enriched` limit 20;

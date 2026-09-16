# ====================================================================
# Step 1.7 | Training set
# ====================================================================
#
# Candidate generation: every product a train user bought at least once in prior.
# Target variable: 1 if the product is in the train order, 0 otherwise.
#
# 8,474,661 rows / 131,209 users / positive rate 9.78% / 828,824 positives
#
# REACHABLE CEILING: 828,824 of the train products appear in prior, 555,793 do not.
# Max recall 0.5986. The per-user F1 ceiling is 0.6986.

# Step 1.7 — training set
create or replace table `deneme-505002.instacart_features.training_set` as

with candidates as (
  select distinct user_id, product_id
  from `deneme-505002.instacart_clean.order_products_enriched`
  where user_id in (select user_id from `deneme-505002.instacart_clean.study_users`)
),

train_items as (
  select distinct o.user_id, t.product_id
  from `deneme-505002.instacart_raw.order_products_train` t
  join `deneme-505002.instacart_clean.orders_train` o on t.order_id = o.order_id
)

select
  c.user_id,
  c.product_id,
  # target variable
  case when ti.product_id is not null then 1 else 0 end as target,

  # user features
  uf.u_n_orders, uf.u_total_items, uf.u_n_products, uf.u_n_aisles, uf.u_n_departments,
  uf.u_avg_basket, uf.u_sd_basket, uf.u_avg_gap, uf.u_sd_gap,
  uf.u_reorder_rate, uf.u_hour_sin, uf.u_hour_cos, uf.u_top_dow, uf.u_days_since_last_order,

  # product features
  pf.p_n_purchases, pf.p_n_users, pf.p_reorder_rate,
  pf.p_second_purchase_rate, pf.p_avg_times_per_user,
  pf.p_avg_cart_position, pf.p_avg_repeat_gap,
  pf.p_popularity_decile, pf.p_reorder_lift,

  # aisle features
  af.a_n_purchases, af.a_n_users, af.a_n_products,
  af.a_reorder_rate, af.a_second_purchase_rate,
  af.a_avg_cart_position, af.a_avg_repeat_gap, af.a_purchases_per_user,

  # department features
  df.d_n_purchases, df.d_n_users, df.d_n_products, df.d_n_aisles,
  df.d_reorder_rate, df.d_second_purchase_rate,
  df.d_avg_cart_position, df.d_avg_repeat_gap, df.d_purchases_per_user,

  # user-product features (the strongest group)
  upf.up_n_purchases, upf.up_first_order, upf.up_last_order,
  upf.up_orders_since_last, upf.up_days_since_last,
  upf.up_order_rate, upf.up_last5_purchases,
  upf.up_avg_cart_position, upf.up_avg_repeat_gap,
  upf.up_share_of_orders

from candidates c
join `deneme-505002.instacart_features.user_product_features` upf
  on c.user_id = upf.user_id and c.product_id = upf.product_id
join `deneme-505002.instacart_features.user_features` uf
  on c.user_id = uf.user_id
join `deneme-505002.instacart_features.product_features` pf
  on c.product_id = pf.product_id
join `deneme-505002.instacart_features.aisle_features` af
  on pf.p_aisle_id = af.aisle_id
join `deneme-505002.instacart_features.department_features` df
  on pf.p_department_id = df.department_id
left join train_items ti
  on c.user_id = ti.user_id and c.product_id = ti.product_id;


select count(*) as n_columns
from `deneme-505002.instacart_features.INFORMATION_SCHEMA.COLUMNS`
where table_name = 'training_set';

select
  count(*) as n_rows,
  count(distinct user_id) as n_users,
  avg(target) as positive_rate,
  sum(target) as n_positives
from `deneme-505002.instacart_features.training_set`;


select
  (select count(*) from `deneme-505002.instacart_features.INFORMATION_SCHEMA.TABLES`
   where table_name = 'user_features_v1') as backup_exists,
  (select count(*) from `deneme-505002.instacart_features.INFORMATION_SCHEMA.COLUMNS`
   where table_name = 'training_set' and column_name in ('u_hour_sin', 'u_hour_cos')) as new_cols,
  (select count(*) from `deneme-505002.instacart_features.INFORMATION_SCHEMA.COLUMNS`
   where table_name = 'training_set' and column_name in ('u_avg_hour', 'up_relative_to_user')) as old_cols;

select
  max(p_avg_repeat_gap) as max_p_gap,
  max(a_avg_repeat_gap) as max_a_gap,
  max(d_avg_repeat_gap) as max_d_gap
from `deneme-505002.instacart_features.training_set`;

# --- STEP 1.7: training_set ---
# row count: 8,474,661 / 131,209 users
# positive_rate = 0.0978 (in line with the expected ~10%)
# n_positives = 828,824
#
# CANDIDATE GENERATION: every product each train user bought at least once in prior.
# a product they never bought does not enter the candidate set, because
# "will they buy it again" is a meaningless question for it.
#
# ============================================================
# REACHABLE CEILING (goes into the README)
# ============================================================
# total product lines in train orders:            1,384,617
# previously bought in prior (reachable):           828,824
# never bought (the model can never catch these):   555,793
# MAX RECALL = 0.5986
#
# this figure is identical to the train reorder rate (59.9%) from Step 1.3.
# the same fact measured two different ways — a consistency check.
#
# F1 CEILING — computed per user (the metric is the mean of per-user F1)
#   per user: 2 * n_reach / (n_reach + n_train), then averaged
#   MACRO CEILING = 0.6986   <- the real ceiling, the number to report
#   median        = 0.7742
#   micro ceiling = 0.7489  <- the old (incorrect) calculation, kept for validation only
#
# WHERE THE GAP COMES FROM:
#   8,602 users (6.6%) have NO product from prior in their train basket.
#   for them the ceiling is 0 — whatever the model does, F1 = 0.
#   the micro calculation pooled all products and hid this.
#
# WHY IT MATTERS: without this ceiling the sentence "I got F1 = 0.42" is meaningless.
# with the ceiling one can say "I reached 60% of the theoretical maximum".
#
# NOTE (Phase 2): for those 8,602 users precision is already 0, so an empty prediction
# and a full prediction both give F1 = 0. For the rest, how user_f1 handles an empty
# prediction affects threshold optimisation — metrics.py will be checked.
#
# VALIDATION: n_positives (828,824) = n_reachable (828,824)
#
# REVISION (Stage 4): training_set was rebuilt
#   removed: up_relative_to_user (up_share_of_orders - u_reorder_rate, mixed units, no new information)
#   changed: u_avg_hour -> u_hour_sin, u_hour_cos (hour is cyclical, order based)
#   refreshed values: p_/a_/d_avg_repeat_gap, a_/d_second_purchase_rate, p_popularity_decile, p_reorder_lift
#   validation: 8,474,661 rows / 131,209 users / 828,824 positives (unchanged), 53 columns
# every reachable positive is present in the training set,
# none were lost during the joins.

select
  countif(abs(t.u_hour_sin - u.u_hour_sin) > 1e-9) as sin_mismatch,
  countif(abs(t.p_avg_repeat_gap - p.p_avg_repeat_gap) > 1e-9) as gap_mismatch
from `deneme-505002.instacart_features.training_set` t
join `deneme-505002.instacart_features.user_features` u using (user_id)
join `deneme-505002.instacart_features.product_features` p using (product_id);




# Check 3 — correlation of each feature with the target
select 'up_orders_since_last' as feature, corr(up_orders_since_last, target) as r from `deneme-505002.instacart_features.training_set`
union all select 'up_last5_purchases', corr(up_last5_purchases, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_n_purchases', corr(up_n_purchases, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_order_rate', corr(up_order_rate, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_share_of_orders', corr(up_share_of_orders, target) from `deneme-505002.instacart_features.training_set`
union all select 'p_avg_repeat_gap', corr(p_avg_repeat_gap, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_days_since_last', corr(up_days_since_last, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_last_order', corr(up_last_order, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_first_order', corr(up_first_order, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_avg_cart_position', corr(up_avg_cart_position, target) from `deneme-505002.instacart_features.training_set`
union all select 'up_avg_repeat_gap', corr(up_avg_repeat_gap, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_n_orders', corr(u_n_orders, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_n_products', corr(u_n_products, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_reorder_rate', corr(u_reorder_rate, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_avg_basket', corr(u_avg_basket, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_avg_gap', corr(u_avg_gap, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_sd_gap', corr(u_sd_gap, target) from `deneme-505002.instacart_features.training_set`
union all select 'u_days_since_last_order', corr(u_days_since_last_order, target) from `deneme-505002.instacart_features.training_set`
union all select 'p_reorder_rate', corr(p_reorder_rate, target) from `deneme-505002.instacart_features.training_set`
union all select 'p_n_purchases', corr(p_n_purchases, target) from `deneme-505002.instacart_features.training_set`
union all select 'p_second_purchase_rate', corr(p_second_purchase_rate, target) from `deneme-505002.instacart_features.training_set`
union all select 'p_reorder_lift', corr(p_reorder_lift, target) from `deneme-505002.instacart_features.training_set`
union all select 'a_reorder_rate', corr(a_reorder_rate, target) from `deneme-505002.instacart_features.training_set`
union all select 'd_reorder_rate', corr(d_reorder_rate, target) from `deneme-505002.instacart_features.training_set`
order by abs(r) desc;



# Check 2 — is order_products_enriched really prior only
select
  o.eval_set,
  count(*) as n_rows
from `deneme-505002.instacart_clean.order_products_enriched` e
join `deneme-505002.instacart_raw.orders` o on e.order_id = o.order_id
group by o.eval_set;

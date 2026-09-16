# ====================================================================
# Step 1.5 | Exploration — groups E and F
# ====================================================================
#
# E — user repertoire: cumulative aisle count, search for a saturation point
# F — user rhythm: average order interval, its standard deviation,
#     relationship between regularity and reorder rate
#
# Both groups contain a correction. The cumulative aisle query was rewritten because
# orders with no new aisle were missing from the average. The regularity analysis was
# rebuilt with three-way banding because order count was not held fixed.

# GROUP E

# cumulative distinct aisle count by order number, per user
# FIX: the previous version only produced rows for orders where a NEW aisle appeared.
# orders with no new aisle never entered the average -> the numbers were inflated.
# now all (user, order) pairs are taken and the new aisle count is attached with a left join.
#
# SURVIVORSHIP BIAS: the average at order 30 comes only from users who REACHED 30 orders.
# the curve mixes individual change with composition change.
# cohort_20_avg: only users with at least 20 prior orders (fixed cohort).
with all_orders as (
  select user_id, order_number
  from `deneme-505002.instacart_clean.orders_prior`
),
user_total as (
  select user_id, max(order_number) as total_orders
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
),
first_visit as (
  select user_id, aisle, min(order_number) as first_order_number
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id, aisle
),
new_per_order as (
  select user_id, first_order_number as order_number, count(*) as new_aisles
  from first_visit
  group by user_id, first_order_number
),
filled as (
  select
    a.user_id,
    a.order_number,
    coalesce(n.new_aisles, 0) as new_aisles
  from all_orders a
  left join new_per_order n
    on a.user_id = n.user_id and a.order_number = n.order_number
),
cumulative as (
  select
    f.user_id,
    f.order_number,
    sum(f.new_aisles) over (
      partition by f.user_id order by f.order_number
      rows between unbounded preceding and current row
    ) as cum_unique_aisles,
    t.total_orders
  from filled f
  join user_total t on f.user_id = t.user_id
)
select
  order_number,
  count(distinct user_id) as n_users,
  avg(cum_unique_aisles) as avg_cum_aisles,
  countif(total_orders >= 20) as n_users_cohort20,
  avg(if(total_orders >= 20, cum_unique_aisles, null)) as cohort20_avg_cum_aisles
from cumulative
group by order_number
order by order_number;
# --- GROUP E FIX ---
# the cumulative aisle query was rewritten.
# OLD BUG: new_per_order only produced rows for orders where a NEW aisle appeared.
#   orders with no new aisle never entered the average -> the numbers were inflated.
# FIX: all (user, order) pairs + left join + coalesce(0)
#
# OLD -> NEW:  order 1: 7.3 -> 7.28  |  order 5: 21 -> 19.10
#              order 10: 29.3 -> 26.36  |  order 30: 42.9 -> 39.16
#
# SURVIVORSHIP BIAS MEASURED (cohort20 = users with at least 20 prior orders):
#   the gap is small and in the opposite direction: order 1 +0.38 / order 10 -0.17
#   the shape of the curve comes from real behaviour, not from composition change.
#
# FINDING: exploration slows down but never stops.
#   +12 aisles between orders 1-5, only +7 aisles between orders 50-99.
#   no saturation point — same conclusion as the "90% threshold" metric.




# at which order this count stops growing
# at which order the user repertoire freezes
with first_visit as (
  select
    user_id,
    aisle,
    min(order_number) as first_order_number
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id, aisle
),
saturation as (
  select
    user_id,
    max(first_order_number) as last_new_aisle_order,
    count(*) as total_aisles
  from first_visit
  group by user_id
),
user_orders as (
  select user_id, max(order_number) as total_orders
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
)
select
  s.last_new_aisle_order,
  count(*) as n_users,
  avg(s.total_aisles) as avg_total_aisles,
  avg(u.total_orders) as avg_total_orders,
  avg(s.last_new_aisle_order / u.total_orders) as avg_saturation_ratio
from saturation s
join user_orders u on s.user_id = u.user_id
group by s.last_new_aisle_order
order by s.last_new_aisle_order;


# at which order the user reaches 90% of their repertoire
with first_visit as (
  select user_id, aisle, min(order_number) as first_order_number
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id, aisle
),
new_per_order as (
  select user_id, first_order_number as order_number, count(*) as new_aisles
  from first_visit
  group by user_id, first_order_number
),
cumulative as (
  select
    user_id,
    order_number,
    sum(new_aisles) over (partition by user_id order by order_number
      rows between unbounded preceding and current row) as cum_aisles,
    sum(new_aisles) over (partition by user_id) as total_aisles
  from new_per_order
),
milestone as (
  select
    user_id,
    min(order_number) as order_at_90pct,
    any_value(total_aisles) as total_aisles
  from cumulative
  where cum_aisles >= 0.9 * total_aisles
  group by user_id
),
user_orders as (
  select user_id, max(order_number) as total_orders
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
)
select
  u.total_orders,
  count(*) as n_users,
  avg(m.order_at_90pct) as avg_order_at_90pct,
  avg(m.order_at_90pct / u.total_orders) as avg_ratio_at_90pct,
  avg(m.total_aisles) as avg_total_aisles
from milestone m
join user_orders u on m.user_id = u.user_id
group by u.total_orders
order by u.total_orders;


# distinct products and aisles per user
with user_repertoire as (
  select
    user_id,
    count(distinct product_id) as n_products,
    count(distinct aisle) as n_aisles,
    count(distinct order_id) as n_orders
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id
)
select
  count(*) as n_users,
  min(n_products) as min_products,
  approx_quantiles(n_products, 100)[offset(25)] as p25_products,
  approx_quantiles(n_products, 100)[offset(50)] as median_products,
  approx_quantiles(n_products, 100)[offset(75)] as p75_products,
  max(n_products) as max_products,
  avg(n_products) as avg_products,
  min(n_aisles) as min_aisles,
  approx_quantiles(n_aisles, 100)[offset(25)] as p25_aisles,
  approx_quantiles(n_aisles, 100)[offset(50)] as median_aisles,
  approx_quantiles(n_aisles, 100)[offset(75)] as p75_aisles,
  max(n_aisles) as max_aisles,
  avg(n_aisles) as avg_aisles
from user_repertoire;



# GROUP F


# average order interval per user
with user_gaps as (
  select
    user_id,
    avg(days_since_prior_order) as avg_gap,
    count(days_since_prior_order) as n_gaps
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
)
select
  count(*) as n_users,
  min(avg_gap) as min_gap,
  approx_quantiles(avg_gap, 100)[offset(25)] as p25_gap,
  approx_quantiles(avg_gap, 100)[offset(50)] as median_gap,
  approx_quantiles(avg_gap, 100)[offset(75)] as p75_gap,
  max(avg_gap) as max_gap,
  avg(avg_gap) as avg_of_avg_gap
from user_gaps;


# standard deviation of order interval per user
with user_gaps as (
  select
    user_id,
    avg(days_since_prior_order) as avg_gap,
    stddev(days_since_prior_order) as sd_gap,
    count(days_since_prior_order) as n_gaps
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
)
select
  count(*) as n_users,
  min(sd_gap) as min_sd,
  approx_quantiles(sd_gap, 100)[offset(25)] as p25_sd,
  approx_quantiles(sd_gap, 100)[offset(50)] as median_sd,
  approx_quantiles(sd_gap, 100)[offset(75)] as p75_sd,
  max(sd_gap) as max_sd,
  avg(sd_gap) as avg_sd
from user_gaps
where n_gaps >= 3;



# do regular users have a different reorder rate
with user_gaps as (
  select
    user_id,
    avg(days_since_prior_order) as avg_gap,
    stddev(days_since_prior_order) as sd_gap,
    count(days_since_prior_order) as n_gaps
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
  having count(days_since_prior_order) >= 3
),
user_reorder as (
  select
    user_id,
    avg(reordered) as reorder_rate,
    count(distinct product_id) as n_products,
    count(distinct aisle) as n_aisles
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id
),
banded as (
  select
    g.user_id,
    g.avg_gap,
    g.sd_gap,
    r.reorder_rate,
    r.n_products,
    r.n_aisles,
    ntile(5) over (order by g.sd_gap) as regularity_band
  from user_gaps g
  join user_reorder r on g.user_id = r.user_id
)
select
  regularity_band,
  count(*) as n_users,
  avg(sd_gap) as avg_sd_gap,
  avg(avg_gap) as avg_gap,
  avg(reorder_rate) as avg_reorder_rate,
  avg(n_products) as avg_n_products,
  avg(n_aisles) as avg_n_aisles
from banded
group by regularity_band
order by regularity_band;


# effect of regularity on reorder rate, holding the interval fixed
with user_gaps as (
  select
    user_id,
    avg(days_since_prior_order) as avg_gap,
    stddev(days_since_prior_order) as sd_gap
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
  having count(days_since_prior_order) >= 3
),
user_reorder as (
  select
    user_id,
    avg(reordered) as reorder_rate
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id
),
gap_banded as (
  select
    g.user_id,
    g.avg_gap,
    g.sd_gap,
    r.reorder_rate,
    case
      when g.avg_gap < 8 then 'A: 0-8 days'
      when g.avg_gap < 13 then 'B: 8-13 days'
      when g.avg_gap < 19 then 'C: 13-19 days'
    else 'D: 19+ days'
    end as gap_band
  from user_gaps g
  join user_reorder r on g.user_id = r.user_id
),
double_banded as (
  select
    *,
    ntile(3) over (partition by gap_band order by sd_gap) as sd_band
  from gap_banded
)
select
  gap_band,
  sd_band,
  count(*) as n_users,
  avg(avg_gap) as avg_gap,
  avg(sd_gap) as avg_sd_gap,
  avg(reorder_rate) as avg_reorder_rate
from double_banded
group by gap_band, sd_band
order by gap_band, sd_band;


select table_name
from `deneme-505002.instacart_features.INFORMATION_SCHEMA.TABLES`
order by table_name;

# --- GROUP F FIX: three-way banding ---
# THE OLD FINDING WAS WRONG: "the regularity effect is clear in mid-frequency groups and vanishes at the extremes"
# why it was wrong: order count was not held fixed. Since the reorder rate climbs
# from 0% to 82% with order count, the bands were confounded.
#
# NEW METHOD: gap_band (4) x order_band (3) x sd_band (3) = 36 cells
#
# FINDING 1 — the regularity effect is present in all 12 (gap x order) combinations.
#   reorder rate difference between sd_band 1 and 3: 4.6 to 11.3 points.
#   example: band B / 16+ orders: 0.679 -> 0.533 (14.6 points)
#   so the effect does not vanish at the extremes — the old finding came from confounding.
#
# FINDING 2 — THE ONLY EXCEPTION: band D (19+ days) / 3-7 orders
#   sd_band 1 and 2 are nearly identical (0.310 vs 0.311).
#   the cause is the 30-DAY CENSORING: 68.7% of the intervals in sd_band 1 are exactly 30.
#   a constant run of 30s pushes the standard deviation artificially toward zero.
#   the "regularity" in this cell is not real, it is a censoring artefact.
#   (avg_gap is highest in sd_band 1 at 27.8 — confirmation)
#
# FINDING 3 — the order count effect is far stronger than regularity.
#   band A: 3-7 orders 0.349 / 16+ orders 0.736 — about 39 points.
#   regularity's largest effect is 11.3 points.
#
# WHY THE RAW BANDS WERE CONFOUNDED:
#   average order count is 58 in band A and 16.8 in band D.
#   frequent buyers are both more regular and have more orders.



# GROUP F CHECK: regularity effect or confounding?
# 1) does the 30-day censoring mechanically compress sd_gap (pct_at_30)
# 2) does the regularity effect survive once order count is held fixed
with user_stats as (
  select
    user_id,
    avg(days_since_prior_order) as avg_gap,
    stddev(days_since_prior_order) as sd_gap,
    countif(days_since_prior_order = 30) / count(days_since_prior_order) as pct_at_30,
    max(order_number) as n_orders
  from `deneme-505002.instacart_clean.orders_prior`
  group by user_id
  having count(days_since_prior_order) >= 3
),
user_reorder as (
  select user_id, avg(reordered) as reorder_rate
  from `deneme-505002.instacart_clean.order_products_enriched`
  group by user_id
),
joined as (
  select
    s.*,
    r.reorder_rate,
    case
      when s.avg_gap < 8 then 'A: 0-8 days'
      when s.avg_gap < 13 then 'B: 8-13 days'
      when s.avg_gap < 19 then 'C: 13-19 days'
      else 'D: 19+ days'
    end as gap_band,
    case
      when s.n_orders < 8 then '1: 3-7 orders'
      when s.n_orders < 16 then '2: 8-15 orders'
      else '3: 16+ orders'
    end as order_band
  from user_stats s
  join user_reorder r on s.user_id = r.user_id
),
triple as (
  select
    *,
    ntile(3) over (partition by gap_band, order_band order by sd_gap) as sd_band
  from joined
)
select
  gap_band,
  order_band,
  sd_band,
  count(*) as n_users,
  avg(n_orders) as avg_n_orders,
  avg(avg_gap) as avg_gap,
  avg(sd_gap) as avg_sd_gap,
  avg(pct_at_30) as avg_pct_at_30,
  avg(reorder_rate) as avg_reorder_rate
from triple
group by gap_band, order_band, sd_band
order by gap_band, order_band, sd_band;

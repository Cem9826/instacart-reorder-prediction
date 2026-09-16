# ====================================================================
# Step 1.1 - 1.2 | Basic counts and eval_set structure
# ====================================================================
#
# Row count per table and distinct value count of the key columns.
# The three eval_set values (prior / train / test) are verified against the data itself.
#
# Result: prior 3,214,874 orders / 206,209 users, train 131,209, test 75,000.
# Every user is either in train or in test, never in both.
# Test order contents were never published, so the study population is the 131,209 train users.

SELECT 'orders' AS tablo, COUNT(*) AS satir FROM `deneme-505002.instacart_raw.orders`
UNION ALL SELECT 'op_prior', COUNT(*) FROM `deneme-505002.instacart_raw.order_products_prior`
UNION ALL SELECT 'op_train', COUNT(*) FROM `deneme-505002.instacart_raw.order_products_train`
UNION ALL SELECT 'products', COUNT(*) FROM `deneme-505002.instacart_raw.products`
UNION ALL SELECT 'aisles', COUNT(*) FROM `deneme-505002.instacart_raw.aisles`
UNION ALL SELECT 'departments', COUNT(*) FROM `deneme-505002.instacart_raw.departments`;

# Step 1.1 : row count per table and distinct value count of key columns
select eval_set, count(*) as n_orders, count(distinct user_id) as n_users
from `deneme-505002.instacart_raw.orders`
group by eval_set;

# Step 1.2 - how many orders and users each eval_set value holds
# how many train orders a single user can have
# whether a user can appear in both train and test

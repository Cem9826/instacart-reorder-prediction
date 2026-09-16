# ====================================================================
# Step 1.8 | Leakage checks
# ====================================================================
#
# Check 1 — source audit: does any feature query touch the train tables
# Check 2 — filter audit: is the prior filter applied everywhere
# Check 3 — correlation scan: does any feature contain the target itself
# Check 4 — experimental test: run in Phase 2, the strongest feature removed and the model retrained
#
# Highest correlation 0.386 — far below the threshold.
# Check 4 result is in the notebook: F1 0.3712 -> 0.3699 (loss 0.0014).

# ============================================================
# STEP 1.8 — LEAKAGE CHECKS
# separate file: sql/08_leakage_checks.sql
# ============================================================

# --- CHECK 1: source audit ---
# every feature query was reviewed by hand.
# sources: order_products_enriched (prior) and orders_prior.
# the ONLY place that touches order_products_train / orders_train:
#   user_features.u_days_since_last_order
# a defined exception — known at prediction time, not leakage.
# the train_items CTE inside training_set produces the TARGET variable only
# and enters no feature.

# --- CHECK 2: filter audit (proven with data) ---
# eval_set distribution of the orders inside order_products_enriched:
#   prior : 32,434,489
#   (NO other rows)
# every feature derives from this view, so the filter is guaranteed.

# --- CHECK 3: correlation scan ---
# HIGHEST CORRELATION: 0.386 (up_last5_purchases)
# far below the 0.9 threshold — no sign of leakage.
#
# top five:
#   up_last5_purchases     +0.386
#   up_share_of_orders     +0.361
#   up_order_rate          +0.282
#   up_n_purchases         +0.248
#   up_days_since_last     -0.217
#
# THE SIGNS POINT THE RIGHT WAY:
# up_days_since_last and up_orders_since_last are NEGATIVE —
# if it has not been bought for a long time the odds of buying it again drop. Expected.
#
# DEVIATION — up_orders_since_last sits 6th (it was expected near the top):
# correlation only measures a LINEAR relationship. This feature probably behaves
# like a threshold: high if 1-2 orders have passed, dropping sharply after 3.
# tree models capture that kind of relationship, correlation does not.
# its position in the feature importance list will be checked in Phase 2.
#
# WEAK FEATURES (near zero on their own):
#   u_reorder_rate  0.007
#   u_sd_gap        0.004
# kept for now — they may be valuable in interaction,
# feature importance will decide.
#
# REVISION (rerun after Stage 4):
#   up_relative_to_user removed from the scan (the column was dropped)
#   p_avg_repeat_gap added: r = -0.120 (12th), sign in the expected direction
#   the top five and their values did not change
#   NOTE: corr() skips NULL rows; p_avg_repeat_gap and up_avg_repeat_gap
#   were computed over non-null rows only

# --- CHECK 4: experimental test ---
# DEFERRED TO PHASE 2.
# the strongest feature is removed and the model retrained.
# if performance does not drop at all, another feature is leaking the same information.

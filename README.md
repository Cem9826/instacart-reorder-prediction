# Instacart — Reorder Prediction

A model that predicts which of a customer's previously purchased products they will buy again in their next order. Plus an impact analysis measuring how useful that prediction actually is for a recommendation system.

Pipeline: BigQuery (SQL) → Python (VS Code) → Looker Studio

**[Interactive dashboard](https://lookerstudio.google.com/reporting/3f7bae42-97c9-4cb5-81b7-f99742854fcd)** · 4 pages: overview, behaviour, model, impact

---

## The question

A recommendation panel has a limited number of slots. Out of the 60-odd products a user has bought before, which ones should it show?

The second question is separate from the first: does the prediction actually help? Even when the model is right, if the user was going to buy that product anyway, the recommendation changes nothing.

---

## Data

[Instacart Market Basket Analysis](https://www.kaggle.com/datasets/psparks/instacart-market-basket-analysis) on Kaggle. Six tables, 3.4 million orders, 32.4 million product lines.

The raw CSVs are not in this repository — download them from the link above and load them into BigQuery. The `outputs/tables/` folder holds the summary CSVs this project produces, which are what the dashboard reads.

| Table | Rows |
|---|---|
| orders | 3,421,083 |
| order_products_prior | 32,434,489 |
| order_products_train | 1,384,617 |
| products | 49,688 |
| aisles | 134 |
| departments | 21 |

The `eval_set` column splits orders three ways: prior (history), train (target), test. The contents of test orders were never published — they were withheld for the Kaggle competition. The work therefore covers only the 131,209 train users.

---

## Scope statement

This section comes before the results, because it determines how the results should be read.

**Order intervals are censored at 30 days.** The `days_since_prior_order` column maxes out at 30. There are 16,976 orders at 29 and 306,137 at 30 — an 18-fold jump. This is not the tail of a natural distribution; Instacart wrote every interval beyond 30 days as 30. A customer who returns after 35 days looks identical to one who returns after 6 months. **Churn cannot be defined with this data.**

**Candidate set ceiling.** The model only evaluates products the user has bought before. 40.1% of the products in train orders were never bought by that user, and the model can never catch them. Maximum reachable F1 = **0.6986** (computed per user).

**Not in the data:** no quantity (one carton of milk or six is indistinguishable), no price or margin, no calendar date (seasonality cannot be measured), no documentation for the `order_dow` encoding (whether 0 is Sunday or Monday is unknown), and no recommendation log (there is no record of what was shown to whom).

**Filters:** `order_number` is capped at 100. Every user has at least 4 orders; in the feature tables this drops to a minimum of 3 because only prior orders are counted.

**Reorder rate measures consumption speed, not loyalty.** This was measured: the correlation between a product's reorder rate and its actual repurchase interval is **r = -0.81** (n = 8,290 products). In the lowest reorder-rate decile the average interval is 56 days; in the highest it is 21.4 days. Thyme gets bought a few times a year — not because the customer is dissatisfied, but because the jar has not run out.

**The `u_days_since_last_order` exception.** This single feature comes from the train order. It is not leakage: how many days have passed since a user's last order is already known at the moment they place a new one.

---

## Method

### Phase 1 — BigQuery

Three separate datasets: `instacart_raw` (raw, never modified), `instacart_clean` (views), `instacart_features` (feature tables).

**Data quality audit.** More than 15 checks were run: null values, out-of-range values, duplicate products within an order, orphan records, duplicate product names. Nothing required cleaning. The 30-day censoring was discovered at this step.

**Exploratory analysis.** Six query groups: time patterns, order sequence, basket structure, product and category, user repertoire, order rhythm.

**Feature tables.** Four tables, all derived from prior orders only:

| Table | Rows | Contents |
|---|---|---|
| user_features | 131,209 | volume, basket, rhythm, behaviour |
| product_features | 49,677 | volume, loyalty, position, rhythm, normalised lift |
| aisle_features / department_features | 134 / 21 | the same metrics at category level |
| user_product_features | 8,474,661 | counts, timing, rates, last-5, position, personal rhythm |

**Training set:** 8,474,661 rows, 131,209 users, 9.78% positive rate.

**Leakage checks.** Four checks: source audit (whether any feature query touches the train tables), filter audit, correlation scan (highest 0.386 — far below threshold), experimental test (below).

### Phase 2 — Python

**Splitting.** Three-way, by user: train 70% / validation 15% / test 15%. A row-level split would put some of a user's products in train and others in validation, letting the model memorise the user and produce a falsely high score. There is zero user overlap between the three sets.

Three sets were used because the threshold and calibration were tuned on validation; test was opened once, for final reporting only.

**Baselines.** Five simple rules were measured before any model was built. How far the model beats this table is the only honest indicator of its performance.

**Models.** Logistic regression first (for interpretability), then LightGBM (for performance).

---

## Results

### Model performance

All values on the validation set, user-level F1:

| Method | F1 | Precision | Recall | AUC | % of ceiling |
|---|---|---|---|---|---|
| LightGBM (per-user threshold) | 0.3771 | 0.3542 | 0.4600 | 0.8378 | 54.0% |
| LightGBM (fixed threshold 0.18) | 0.3712 | 0.3346 | 0.5082 | 0.8378 | 53.1% |
| Logistic regression | 0.3594 | 0.3029 | 0.5478 | 0.8267 | 51.5% |
| Baseline 4: order rate ≥ 0.35 | 0.3178 | 0.2408 | 0.6153 | — | 45.5% |
| Baseline 2: repeat the last order | 0.3123 | 0.2873 | 0.4283 | — | 44.7% |
| Baseline 3: top 10 most purchased | 0.3068 | 0.2754 | 0.4844 | — | 43.9% |
| Baseline 1: recommend every candidate | 0.2153 | 0.1318 | 0.9344 | — | 30.8% |
| Baseline 0: recommend nothing | 0.0000 | 0.0000 | 0.0000 | — | 0% |

**Final result on the test set: F1 = 0.3777.** The gap from validation is 0.0006 — the model has not overfitted, and the threshold choice does not rest on a quirk of the validation set.

In practical terms: the model recommends about 8 products per user and gets 3 right.

The gain over simple rules is 0.0599. Logistic regression alone delivers roughly 70% of that; LightGBM adds 0.0177.

### Findings

**1. Timing is a stronger signal than volume.** The "repeat the last order" rule (0.3123) beats "recommend the 10 most purchased" (0.3068). The two strongest logistic regression coefficients are also timing: `up_days_since_last` (-0.499) and `up_orders_since_last` (-0.389). In the feature importance ranking, the entire top five are user-product features, accounting for 78.7% of total gain.

**2. Users change what they buy, not how much.** As order count rises, the reorder rate climbs from 0% to 82%, but average basket size stays flat at around 10.

**3. The repertoire never saturates.** 7.3 aisles on the first order, 26.4 by the 10th, 39.2 by the 30th, 52.4 by the 99th. The rate of increase keeps falling but never reaches zero. The first five orders add 12 aisles; the fifty orders between 50 and 99 add only 7. Survivorship bias was checked: the curve drawn from users with at least 20 orders does not diverge from the overall curve (a 0.17-aisle gap at order 10).

**4. Regularity raises the reorder rate, but order count matters far more.** Holding both order interval and order count fixed, regular users have a higher reorder rate than irregular ones in all 12 of 12 combinations (between 4.6 and 11.3 points). The order count effect, by contrast, is 39 points. In the raw bands these two effects were confounded.

**5. The model is never confident, and the uncertainty is structural.** Only 3% of all predictions exceed 0.50. Every product a user has ever bought counts as a candidate, but on average only 6.3 of them appear in the next order.

### Calibration

When the model says 0.30, is the true rate around 30%? Measured across twenty bins: **mean absolute error 0.0007**. In all twenty bins the deviation stays below 0.0041.

Isotonic regression was not applied — the condition never arose. The calibration is this good because of three design choices: `objective='binary'`, no class weighting, and early stopping on `binary_logloss`.

### Leakage check (Check 4)

The strongest features were removed and the model retrained from scratch:

| Model | F1 | Rounds | Loss |
|---|---|---|---|
| Full model | 0.3712 | 553 | — |
| `up_days_since_last` removed | 0.3699 | 682 | 0.0014 |
| `up_last5_purchases` removed | 0.3709 | 607 | 0.0004 |

The losses are near zero. This is not a leakage signal — the timing information lives in several columns, all of them computed from prior orders only. With leakage the absolute score would sit near the ceiling; 0.3712 is 53% of it.

Permutation importance was compared against the gain ranking and the two lists disagreed. `up_last5_purchases` ranks first on gain (33.5%) but fourth on permutation; `up_days_since_last` ranks fifth on gain but first on permutation. The cause is redundancy: when a feature with a backup is shuffled, the model falls back on the other columns.

---

## Impact analysis

The model predicts correctly. But does anything actionable follow from that prediction?

### Probability bands

Predictions were split into three bands (boundaries 0.10 and 0.50):

| Band | Share of rows | Share of purchases | Actual purchase rate |
|---|---|---|---|
| Obvious (≥ 0.50) | 3.0% | 19.7% | 0.643 |
| Incremental (0.10–0.50) | 25.1% | 54.8% | 0.215 |
| Low (< 0.10) | 71.9% | 25.5% | 0.035 |

The expectation was that most correct predictions would pile up in the obvious band. The opposite happened: only 19.7% of purchases fall there, while 54.8% sit in the region where the model is undecided.

Sensitivity to the boundary choice was checked. Across four different boundary sets the obvious band's share ranges from 12.6% to 28.5% — never approaching a majority.

The incremental band can be separated internally: within-band AUC is 0.6643, with a 4.12x gap between the top and bottom deciles. The top 3 deciles amount to 4.8 pairs per user and 26.8% of all purchases — which fits a five-slot recommendation quota.

### Matching analysis

The question: does a product being in the last order *cause* it to be bought in the next one?

The raw difference is 0.2188. But the two groups start out very different: products present in the last order are bought in 77% of that user's orders, versus 21% for those absent.

Propensity score matching was applied. A common support problem emerged — the propensity model's AUC was 0.9681, meaning the treatment is almost entirely determined by the matching covariates. The analysis was narrowed to the overlap region ([0.10 – 0.90]).

Match quality was checked: all eight covariates fell below the |SMD| < 0.10 threshold. `up_order_rate` dropped from 2.3695 to -0.0161.

| | Value |
|---|---|
| Matched treatment group | 37.7% |
| Matched control group | 26.3% |
| ATT | 0.1133 [95% CI: 0.1089 – 0.1178] |
| Raw difference | 0.2188 |
| Confounding | 0.1055 (48.2%) |

Almost half of the raw difference was confounding.

### Placebo test

Can that 0.1133 be read causally?

Instead of a randomly assigned fake treatment, a temporal negative control was used: **was the product in the second-to-last prior order?** The treatment cannot affect the past, so if the matching is sound the difference here should be near zero.

| | Value |
|---|---|
| Placebo effect | **-0.1570** |
| Real effect (ATT) | 0.1133 |
| Ratio | 139% |

**The test failed.** The placebo effect is larger than the real effect and points the other way. The matched groups differed even in the period before the treatment.

A second attempt added rhythm covariates (`up_avg_repeat_gap`, `up_days_since_last`, `u_avg_gap`, `u_sd_gap`). It got worse: the propensity AUC rose to 0.9980, balance dropped from 8/8 to 9/12, and the placebo effect reached -0.5533.

### Sensitivity analysis

A hidden factor would only need to shift the odds of treatment by a factor of **1.8** to erase the effect entirely. In observational work, values around 4-5 are considered robust; 1.8 is fragile.

There is no need to hypothesise such a factor anyway — the placebo test showed one actually exists.

### Conclusion

**0.1133 cannot be reported as a causal effect.** The association between a product being in the last order and being bought again is strong, but this data cannot separate how much of it is "the effect of seeing it in the basket" from how much is the product's consumption rhythm.

This is not a failure. It is the self-checking part of the analysis doing its job. Without the placebo test, 0.1133 would have been reported as "the effect of being in the last order" — and it would have been wrong.

---

## What the data supports and what it does not

**Supported:** the model reaches F1 = 0.3777 on unseen users. The probabilities are calibrated. 54.8% of purchases sit in the incremental band. The top 3 deciles of that band cover 4.8 pairs per user and 26.8% of all purchases.

**Not supported:** the effect of a recommendation (there is no recommendation log in the data). A causal reading of 0.1133. Which band is the action zone. Churn.

**What it would take to measure:** a randomised A/B test. Recommendations should go to the top deciles of the incremental band, with the obvious band held as control. The base rate in the incremental band is 21.5%; detecting a 3-point difference at 80% power needs roughly 3,500 users per arm.

---

## Repository structure

```
├── sql/                    one .sql file per step
├── notebook/
│   └── instaract.ipynb     exploration, model, impact analysis
├── src/
│   ├── data_loader.py      parquet reading, memory optimisation
│   ├── splitter.py         user-level three-way split
│   └── metrics.py          user-level F1, precision, recall
├── outputs/
│   ├── figures/            11 charts
│   ├── tables/             summary CSVs
│   └── models/             trained LightGBM
└── README.md
```

---

## Running it

Required libraries: `pandas`, `numpy`, `google-cloud-bigquery`, `db-dtypes`, `lightgbm`, `scikit-learn`, `matplotlib`, `seaborn`, `pyarrow`.

1. Run the files under `sql/` in order in BigQuery. This creates the three datasets and the feature tables.
2. The download cell in the notebook writes the training set to disk as parquet (~130 min, 884 MB). If the file already exists the cell is skipped.
3. Run the notebook from top to bottom.

Note: Cloud Storage is unavailable in Sandbox mode, so the export was done by streaming Arrow batches from BigQuery directly into parquet.

---

## Technical notes

**Memory.** 8.47 million rows × 53 columns on a machine with 8 GB of RAM. Type optimisation (int64 → int8/int16/int32, float64 → float32) cut memory use from 3.6 GB to 1.3 GB.

**Determinism.** `product_id` was added as a second sort key to the NTILE functions, so products with equal sales fall into the same decile on every run. Before the fix, 1,198 products changed decile between two runs.

**Cyclical hour.** `u_hour_sin` and `u_hour_cos` replaced `u_avg_hour`. The arithmetic mean of hour 23 and hour 1 was coming out as 12.

**Product purchase interval.** `p_avg_repeat_gap` was first computed as the mean of `days_since_prior_order`, which measured the user's order interval rather than the product's purchase interval. It was corrected: for each (user, product) pair, the days between first and last purchase divided by purchases minus one. Baking Powder went from 7.6 to 83.1 days; Banana from 10.5 to 18.6. The correlation between the old and new values is 0.20.

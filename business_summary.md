# Instacart — Business Summary

## What we asked

A grocery site's recommendation panel has limited space. Out of the 60-odd products a customer has bought before, which ones should it show?

Behind that sits a second question: does the recommendation actually help? If the customer was going to buy the product anyway, showing it changes nothing.

---

## What we found

**The model recommends 8 products per customer and gets 3 right.** With no modelling at all — just repeating the previous basket — you would get 3 out of 10. The model does a little better, but it is no miracle.

There is a reason it cannot do much better: 40% of what customers buy are products they have never bought before. The model cannot see those, because it only chooses from past purchases.

**Timing is the most useful signal.** How recently a customer bought a product, and at what intervals, matters more than how many times they have bought it in total. Two customers may have bought the same product the same number of times; what separates them is how long it has been since the last purchase.

**A frequently reordered product does not mean a loyal customer.** Milk gets bought every two weeks, thyme every three months. That gap is consumption speed, not preference. Nobody rebuys thyme because the jar has not run out. We measured this: products with a low reorder rate have markedly longer purchase intervals.

**Customers never stop trying new things.** The first order touches about 7 different aisles; by the 30th it is 39. The rate slows down, but calling it a stop would be wrong.

---

## What should be done

The model can rank what to recommend to whom. What it cannot say is which recommendation actually makes a difference.

We split the predictions into three groups:

- **Will buy anyway.** The model is confident. Spending a slot here is a waste of space. 20% of all purchases.
- **Undecided.** The model is genuinely unsure. This is the only place a reminder could tip the balance. 55% of purchases.
- **Will not buy.** The model is confident it is a no. A recommendation here is wasted.

The surprising part: most purchases sit in the undecided zone. The opportunity area is bigger than expected.

But this is where caution is needed.

---

## What we do not know

**We could not measure the effect of a recommendation.** There is no record of recommendations in the data. Who was shown what, and whether they clicked, is unknown. We cannot say "adding recommendations here will lift sales by X".

We tried to test it. We asked whether a product being in the previous basket *causes* it to be bought in the next one, matching customers with similar habits and comparing them.

The result looked promising. But we ran one more check — a check on the method itself — and **that check failed**. Which means the number we found is not reliable.

We are writing this down rather than hiding it, because without that check a wrong result would have been reported.

**We also cannot measure churn.** In the data, order intervals are cut off at 30 days. A customer returning after 35 days looks identical to one returning after 6 months.

---

## What comes next

The effect of a recommendation can only be measured by experiment. A simple setup:

Customers are split randomly into two groups. One group sees recommendations from the undecided zone; the other does not. A few weeks later the two groups' purchases are compared.

3,500 customers per group is enough. Without this experiment, nothing definitive can be said about the value of the recommendation.

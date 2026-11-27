# Breaking Games holiday game plan

I used SQL to work out what Breaking Games should reorder before the holidays, where ad tracking needed a closer look, and what to test at checkout. The report recommends stocking Eldervale first, checking paid tracking before adding spend, and testing a simpler one-product checkout.

The report covers a January through July sales summary, but its source does not state the sales year. It uses a separate July 2025 checkout comparison. It records $61,085.33 in sales, 1,972 units, and 50.5% of sales from the top three Eldervale variants. Organic Search recorded a 0.479% observed checkout rate versus 0.124% for Paid Social. Meta spend was $37,200.94. These are report findings, not outputs from the synthetic fixture below.

Start here:

- [Report](./breaking-games-report.md)
- [PDF report](./Breaking-Games-Holiday-Game-Plan.pdf)
- [Public input contract](./sql/schema.sql)
- [Synthetic fixture](./sql/fixture.sql)
- [Analysis queries](./sql/analysis.sql)

## How the analysis works

The [analysis query file](./sql/analysis.sql) is a small edition of the work behind the report. It keeps the decision questions visible without copying the private database, customer fields, campaign identifiers, or source rows.

| Question | Public query behavior |
| --- | --- |
| What should be reordered? | Rolls sales rows up to product grain before ranking and calculating top-three and top-ten concentration. |
| How much referral coverage exists? | Uses an exact canonical product path and `EXISTS`, so duplicate referral rows cannot multiply a product. This is coverage, not attribution. |
| Which channels compare well? | Maps referrers to channels, then calculates checkout sessions divided by pageviews at channel grain. |
| What paid spend is visible? | Sums active and inactive aggregate spend without exposing campaign names or IDs. |
| What should be tested at checkout? | Deduplicates line items to cart grain, counts one-product carts only when exactly one mapped product is present and no line is unknown, excludes a cart when any quantity is above five, and compares clean carts and completed orders in the same July 2025 month. |

## Run the SQL

The files use SQLite and need no package install. Supply sales and traffic inputs for the comparable scope you choose, or run the included fixture. From the repository root, run:

```sh
sqlite3 :memory: ".read sql/schema.sql" ".read sql/fixture.sql" ".read sql/analysis.sql"
```

The fixture is deliberately tiny and synthetic. Its numbers only prove that the queries run and handle duplicate cart lines, null or blank referrers, a missing landing path, a quantity exclusion, duplicate order keys, and dates outside July 2025. They are not Breaking Games findings. I did not run these files against the private sales database.

## Limits

- The report keeps the sales year as unknown. The January through July sales summary has no year label.
- The report states a 50.8% July 2025 cart-abandonment comparison but does not publish the exact clean-July cart numerator. The query computes that numerator from supplied input; the README does not present the 50.8% as independently rerun here.
- Referral checkout rates are observational aggregates. The source does not link a referral checkout to a named sale, and the public coverage query does not claim product attribution.
- Aggregate paid spend is not ROAS. The public edition omits campaign-level names, IDs, and row-level results.
- The quantity-above-five rule is a review filter. It does not prove that a cart was automated, fraudulent, or a reseller order.
- Raw exports, derived row-level inputs, private schemas, source links, and secrets stay out of this repository.

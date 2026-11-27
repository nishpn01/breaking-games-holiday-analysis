-- SQLite analysis queries.
-- The fixture is synthetic. The result sets are not published findings.

DROP VIEW IF EXISTS temp.analysis_settings;
CREATE TEMP VIEW analysis_settings AS
SELECT '2025-07' AS analysis_month;

-- Product rollup and rank. Roll up first because the input contract allows
-- multiple sales rows per product.
DROP VIEW IF EXISTS temp.product_rollup;
CREATE TEMP VIEW product_rollup AS
SELECT
    pc.product_slug,
    pc.product_title,
    SUM(ps.units_sold) AS units_sold,
    SUM(ps.revenue_usd) AS revenue_usd
FROM product_catalog AS pc
JOIN product_sales AS ps
    ON ps.product_slug = pc.product_slug
GROUP BY pc.product_slug, pc.product_title
HAVING SUM(ps.units_sold) > 0;

DROP VIEW IF EXISTS temp.product_ranked;
CREATE TEMP VIEW product_ranked AS
SELECT
    product_slug,
    product_title,
    units_sold,
    revenue_usd,
    ROW_NUMBER() OVER (
        ORDER BY revenue_usd DESC, product_slug
    ) AS revenue_rank
FROM product_rollup;

DROP VIEW IF EXISTS temp.product_ranked_with_total;
CREATE TEMP VIEW product_ranked_with_total AS
SELECT
    pr.*,
    SUM(pr.revenue_usd) OVER () AS cohort_revenue_usd
FROM product_ranked AS pr;

-- Reorder view: exact top-N rows with a deterministic tie-breaker.
SELECT
    revenue_rank,
    product_title,
    ROUND(revenue_usd, 2) AS revenue_usd,
    units_sold,
    ROUND(
        100.0 * revenue_usd / NULLIF(cohort_revenue_usd, 0),
        1
    ) AS share_of_positive_revenue_pct
FROM product_ranked_with_total
WHERE revenue_rank <= 10
ORDER BY revenue_rank;

-- Concentration check. The denominator is the rolled-up positive-unit
-- product population, not a line-item count or a limited top-N slice.
SELECT
    ROUND(SUM(CASE WHEN revenue_rank <= 3 THEN revenue_usd ELSE 0 END), 2)
        AS top_3_revenue_usd,
    ROUND(SUM(CASE WHEN revenue_rank <= 10 THEN revenue_usd ELSE 0 END), 2)
        AS top_10_revenue_usd,
    ROUND(SUM(revenue_usd), 2) AS positive_product_revenue_usd,
    ROUND(
        100.0 * SUM(CASE WHEN revenue_rank <= 3 THEN revenue_usd ELSE 0 END)
        / NULLIF(SUM(revenue_usd), 0),
        1
    ) AS top_3_revenue_pct,
    ROUND(
        100.0 * SUM(CASE WHEN revenue_rank <= 10 THEN revenue_usd ELSE 0 END)
        / NULLIF(SUM(revenue_usd), 0),
        1
    ) AS top_10_revenue_pct
FROM product_ranked;

-- Referral coverage. EXISTS prevents repeated referral rows from multiplying
-- a product. landing_page is required to be the canonical path in this public
-- contract. Coverage is not product-level attribution.
WITH sold_products AS (
    SELECT
        pc.product_slug,
        pc.product_title
    FROM product_catalog AS pc
    JOIN product_sales AS ps
        ON ps.product_slug = pc.product_slug
    GROUP BY pc.product_slug, pc.product_title
    HAVING SUM(ps.units_sold) > 0
), coverage AS (
    SELECT
        sp.product_slug,
        CASE WHEN EXISTS (
            SELECT 1
            FROM referral_traffic AS rt
            WHERE TRIM(LOWER(rt.landing_page))
                = '/products/' || LOWER(sp.product_slug)
        ) THEN 1 ELSE 0 END AS has_exact_referral
    FROM sold_products AS sp
)
SELECT
    COUNT(*) AS sold_product_count,
    SUM(has_exact_referral) AS products_with_exact_referral,
    SUM(CASE WHEN has_exact_referral = 0 THEN 1 ELSE 0 END)
        AS products_without_exact_referral,
    ROUND(
        100.0 * SUM(CASE WHEN has_exact_referral = 0 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        1
    ) AS missing_referral_pct
FROM coverage;

-- Channel comparison. The mapping follows the authored channel taxonomy while
-- keeping the output at aggregate channel grain.
DROP VIEW IF EXISTS temp.channelized_referrals;
CREATE TEMP VIEW channelized_referrals AS
SELECT
    CASE
        WHEN COALESCE(NULLIF(LOWER(TRIM(referrer)), ''), 'direct') = 'direct'
            THEN 'Direct'
        WHEN LOWER(TRIM(referrer)) IN ('facebook', 'instagram', 'meta')
            THEN 'Paid Social'
        WHEN LOWER(TRIM(referrer)) IN ('googlesyndication', 'syndicatedsearch')
            THEN 'Paid Search / Display'
        WHEN LOWER(TRIM(referrer)) IN (
            'google', 'bing', 'duckduckgo', 'brave', 'yahoo!',
            'yandex', 'ecosia', 'baidu', 'live'
        ) THEN 'Organic Search'
        WHEN LOWER(TRIM(referrer)) IN ('gmail', 'klaviyo', 'deref-gmx')
            THEN 'Email'
        WHEN LOWER(TRIM(referrer)) IN (
            'boardgamegeek', 'boardgamearena', 'kickstarter', 'mapyourshow',
            'paxsite', 'gencon', 'printplaygames', 'boardlife'
        ) THEN 'Community / Referral'
        WHEN LOWER(TRIM(referrer)) IN (
            'reddit', 'youtube', 'tiktok', 'pinterest', 'linkedin', 'nextdoor'
        ) THEN 'Organic Social'
        ELSE 'Other'
    END AS channel,
    pageviews,
    checkout_sessions
FROM referral_traffic;

SELECT
    channel,
    SUM(pageviews) AS pageviews,
    SUM(checkout_sessions) AS checkout_sessions,
    ROUND(
        100.0 * SUM(checkout_sessions) / NULLIF(SUM(pageviews), 0),
        3
    ) AS observed_checkout_rate_pct
FROM channelized_referrals
GROUP BY channel
ORDER BY observed_checkout_rate_pct DESC, pageviews DESC, channel;

-- Representative aggregate spend query. Campaign names, IDs, and row-level
-- results are intentionally outside the public input contract.
SELECT
    ROUND(SUM(spend_usd), 2) AS aggregate_paid_spend_usd
FROM paid_media_spend
WHERE LOWER(TRIM(delivery_status)) IN ('active', 'inactive');

-- Cart grain and quantity filter. A cart is excluded in full if any line has a
-- quantity above five. COUNT(DISTINCT product_slug) is safe for duplicate lines
-- and leaves an unmapped product as zero distinct mapped products.
DROP VIEW IF EXISTS temp.cart_level;
CREATE TEMP VIEW cart_level AS
SELECT
    cart_key,
    MIN(created_at) AS created_at,
    COUNT(DISTINCT NULLIF(TRIM(product_slug), '')) AS distinct_mapped_products,
    SUM(CASE WHEN NULLIF(TRIM(product_slug), '') IS NULL THEN 1 ELSE 0 END)
        AS unknown_product_line_count,
    MAX(lineitem_quantity) AS max_lineitem_quantity
FROM checkout_lines
WHERE cart_key IS NOT NULL
GROUP BY cart_key;

DROP VIEW IF EXISTS temp.clean_cart_level;
CREATE TEMP VIEW clean_cart_level AS
SELECT *
FROM cart_level
WHERE max_lineitem_quantity <= 5;

SELECT
    COUNT(*) AS raw_cart_count,
    SUM(CASE WHEN distinct_mapped_products = 1
                  AND unknown_product_line_count = 0
             THEN 1 ELSE 0 END)
        AS one_product_cart_count,
    SUM(CASE WHEN distinct_mapped_products = 1 THEN 1 ELSE 0 END)
        AS one_mapped_product_cart_count,
    SUM(CASE WHEN unknown_product_line_count > 0 THEN 1 ELSE 0 END)
        AS cart_with_unknown_product_line_count,
    SUM(CASE WHEN max_lineitem_quantity > 5 THEN 1 ELSE 0 END)
        AS excluded_quantity_cart_count,
    (SELECT COUNT(*) FROM clean_cart_level) AS clean_cart_count
FROM cart_level;

-- Same-month checkout comparison. This keeps the source's proxy formula but
-- fixes the window mismatch by filtering carts and distinct orders to July
-- 2025. The result is a comparison proxy, not a causal abandonment estimate.
WITH month_counts AS (
    SELECT
        s.analysis_month,
        (
            SELECT COUNT(*)
            FROM clean_cart_level AS cl
            WHERE SUBSTR(cl.created_at, 1, 7) = s.analysis_month
        ) AS clean_carts_in_month,
        (
            SELECT COUNT(DISTINCT co.order_key)
            FROM completed_orders AS co
            WHERE SUBSTR(co.order_date, 1, 7) = s.analysis_month
        ) AS completed_orders_in_month
    FROM analysis_settings AS s
)
SELECT
    analysis_month,
    clean_carts_in_month,
    completed_orders_in_month,
    ROUND(
        100.0 * clean_carts_in_month
        / NULLIF(clean_carts_in_month + completed_orders_in_month, 0),
        1
    ) AS abandonment_proxy_pct
FROM month_counts;

-- Reusable checks. These do not assert the fixture's exact values.
SELECT 'product ranks are unique' AS check_name,
       CASE WHEN COUNT(*) = COUNT(DISTINCT revenue_rank)
            THEN 'PASS' ELSE 'FAIL' END AS status
FROM product_ranked
UNION ALL
SELECT 'cart view is one row per non-null cart key',
       CASE WHEN COUNT(*) = COUNT(DISTINCT cart_key)
            THEN 'PASS' ELSE 'FAIL' END
FROM cart_level
UNION ALL
SELECT 'quantity filter partitions clean and excluded carts',
       CASE WHEN NOT EXISTS (
                SELECT 1 FROM clean_cart_level
                WHERE max_lineitem_quantity > 5
            )
            AND (SELECT COUNT(*) FROM cart_level)
                = (SELECT COUNT(*) FROM clean_cart_level)
                + (SELECT COUNT(*) FROM cart_level
                   WHERE max_lineitem_quantity > 5)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'channel mapping has no null output channel',
       CASE WHEN COUNT(*) = COUNT(channel)
            THEN 'PASS' ELSE 'FAIL' END
FROM channelized_referrals;

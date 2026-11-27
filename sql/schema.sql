-- SQLite public input contract.
-- These tables describe the minimum fields needed by analysis.sql.
-- Do not copy raw exports, customer fields, billing fields, campaign names, or
-- private identifiers into this contract.

PRAGMA foreign_keys = ON;

CREATE TABLE product_catalog (
    product_slug TEXT PRIMARY KEY,
    product_title TEXT NOT NULL
);

-- Multiple rows per product are allowed. analysis.sql rolls them up before
-- ranking, which keeps the ranking grain explicit.
CREATE TABLE product_sales (
    product_slug TEXT NOT NULL,
    units_sold INTEGER NOT NULL,
    revenue_usd REAL NOT NULL,
    FOREIGN KEY (product_slug) REFERENCES product_catalog (product_slug)
);

-- One row is an aggregate traffic record for a referrer and canonical landing
-- path. A null or blank referrer is treated as direct traffic by the query.
CREATE TABLE referral_traffic (
    referrer TEXT,
    landing_page TEXT,
    pageviews INTEGER NOT NULL,
    checkout_sessions INTEGER NOT NULL
);

-- No campaign name or campaign ID is needed for the aggregate spend check.
CREATE TABLE paid_media_spend (
    delivery_status TEXT,
    spend_usd REAL NOT NULL
);

-- This is a line-item contract. The query collapses it to one row per cart_key
-- before counting carts. product_slug may be null when the item is unmapped.
CREATE TABLE checkout_lines (
    cart_key TEXT NOT NULL,
    created_at TEXT NOT NULL,
    product_slug TEXT,
    lineitem_quantity INTEGER NOT NULL
);

-- One order may appear more than once in an export. The query counts distinct
-- order_key values inside the same analysis month as the carts.
CREATE TABLE completed_orders (
    order_key TEXT NOT NULL,
    order_date TEXT NOT NULL
);

-- Clearly synthetic fixture for a smoke test. These names and numbers are not
-- Breaking Games data and must not be presented as published findings.

INSERT INTO product_catalog (product_slug, product_title) VALUES
    ('example-alpha', 'Example game alpha'),
    ('example-beta', 'Example game beta'),
    ('example-gamma', 'Example game gamma'),
    ('example-delta', 'Example game delta'),
    ('example-zero', 'Example game with no units');

-- The repeated alpha rows exercise the product rollup before ranking.
INSERT INTO product_sales (product_slug, units_sold, revenue_usd) VALUES
    ('example-alpha', 2, 20.00),
    ('example-alpha', 1, 10.00),
    ('example-beta', 3, 15.00),
    ('example-gamma', 1, 5.00),
    ('example-delta', 4, 8.00),
    ('example-zero', 0, 0.00);

-- Alpha has duplicate path rows. Null and blank referrers should map to
-- Direct. The null landing path must not count as product coverage.
INSERT INTO referral_traffic
    (referrer, landing_page, pageviews, checkout_sessions) VALUES
    ('google', ' /products/example-alpha ', 100, 5),
    (NULL, '/products/example-alpha', 50, 1),
    ('instagram', '/products/example-beta', 80, 4),
    ('', '/products/example-gamma', 40, 2),
    ('unknown-site', NULL, 7, 0);

INSERT INTO paid_media_spend (delivery_status, spend_usd) VALUES
    ('active', 12.50),
    ('inactive', 7.50),
    ('draft', 100.00);

-- Cart A has duplicate line items for one product. Cart C is excluded in full
-- because one line quantity is above five. Cart F has one mapped product and
-- one unmapped line, so it must not count as a confirmed one-product cart.
INSERT INTO checkout_lines
    (cart_key, created_at, product_slug, lineitem_quantity) VALUES
    ('cart-a', '2025-07-03T10:00:00Z', 'example-alpha', 1),
    ('cart-a', '2025-07-03T10:00:00Z', 'example-alpha', 1),
    ('cart-b', '2025-07-05T10:00:00Z', 'example-beta', 1),
    ('cart-b', '2025-07-05T10:00:00Z', 'example-gamma', 1),
    ('cart-c', '2025-07-06T10:00:00Z', 'example-alpha', 6),
    ('cart-d', '2025-06-28T10:00:00Z', 'example-beta', 1),
    ('cart-e', '2024-07-28T10:00:00Z', 'example-gamma', 1),
    ('cart-f', '2025-07-09T10:00:00Z', 'example-alpha', 1),
    ('cart-f', '2025-07-09T10:00:00Z', NULL, 1);

-- order-1 is repeated to prove that the month count uses distinct order keys.
INSERT INTO completed_orders (order_key, order_date) VALUES
    ('order-1', '2025-07-04'),
    ('order-1', '2025-07-04'),
    ('order-2', '2025-07-08'),
    ('order-3', '2025-06-30');

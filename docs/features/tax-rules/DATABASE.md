# Database impact

Verified against: xorder-pos `a6f5fe5` (+ uncommitted work), xorder-cloud `06bc8e3` (+ uncommitted work, none in tax files) · Updated 2026-10-26

## Tables and constraints
POS branch PostgreSQL (apps/xorder-pos/lib/data/postgres/migrations.dart): `pos_tax_groups(id, restaurant_id, name_en, name_ar, rate_bp integer NOT NULL, is_default, is_active, created_at)`, `CHECK (rate_bp BETWEEN 0 AND 10000)` (:1661-1662), `UNIQUE (restaurant_id, name_en)`, one default per restaurant by a partial unique index (:1669). `pos_money_config(restaurant_id PK, payload jsonb, synced_at)` holds `charges`, `tax_mode`, `tax_rules` (apps/xorder-pos/lib/data/postgres/money_config_codec.dart:61). `pos_restaurants.tax_mode` (migration 26, :2373) exists but is only the migration default; reports prefer the payload's value (apps/xorder-pos/lib/data/postgres/postgres_reports_repository.dart:514-528). `pos_order_taxes` records one row per rate per order (migration 16). Orders do **not** record the tax mode.
Cloud: `tax_rules(id, restaurant_id → restaurants cascade, name, rate_bp unsigned int, mode string(12) default 'exclusive', applies_to json, sort_order, timestamps)` (apps/xorder-cloud/apps/api/database/migrations/2026_09_02_000400_create_pos_money_config_tables.php:24-33). Tenant boundary: `BelongsToRestaurant` trait on the model (apps/xorder-cloud/apps/api/app/Models/TaxRule.php:12); tenant test UNVERIFIED.

## Proposed changes
None made. Proposed, not built (XORD-028): record the mode on the order.

## Transactions and concurrency
`saveMoneyConfig` runs in one transaction; the default group row is read `FOR UPDATE`, so two tills saving at once serialise and the last write wins (no version check; same as before for the payload).

## Indexes and query performance
Existing partial unique index serves the default-group UPDATE. One row touched. No new index.

## Migration and rollback plan
No migration. Rollback is reverting code; the data is ordinary config.

## Backup/data access constraints
No real database was read or written. PostgreSQL behaviour was exercised only on the local throwaway test database of this checkout (`xorder_pos_test_*`), by the test suite.

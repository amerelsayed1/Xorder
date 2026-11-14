# Database impact: Self-service restaurant signup

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
Rows created per signup (one transaction, `C:app/Services/RestaurantProvisioningService.php:108-150`): `restaurants` (1, slug unique: `C:database/migrations/2026_06_27_002001_create_restaurants_table.php:15`), `users` (1 owner; see `auth-login` DATABASE for columns), `roles` (system roles, `C:app/Services/TenantRoleService.php:52-67`), `restaurant_features` (one row per feature key, `C:app/Services/RestaurantFeatureService.php:23-37`), `pos_licences` (1, `C:app/Services/LicenceIssuer.php`), audit entry `pos_licence.issued`.

## Relationships
Owner `users.restaurant_id` → restaurant; roles and features belong to the restaurant.

## Shared entities across applications
The licence is consumed by the POS (`pos-licensing`).

## Proposed changes
None.

## Transactions and concurrency
Single `DB::transaction`; the licence issue runs as a nested savepoint (`RestaurantProvisioningService.php:139-142`). Slug uniqueness is checked in code and by the unique index.

## Indexes and query performance
`restaurants.slug` unique; `users.email` unique at creation (later nullable; current uniqueness UNVERIFIED).

## PostgreSQL vs SQLite differences
Not established for this feature.

## Migration and rollback plan
No change proposed.

## Backup/data access constraints
Contains personal data (owner name, email, WhatsApp number); no backup read.

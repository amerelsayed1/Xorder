# Database impact: Tenant isolation (restaurant scope)

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
Tenant-owned tables carry `restaurant_id` (foreign key to `restaurants`); the list of models using the trait is in `FEATURE_INVENTORY.md`/`FEATURE.md`. `users.restaurant_id` is nullable, indexed, with a foreign key (`C:database/migrations/2026_06_27_002001_create_restaurants_table.php:35-45`); platform users have null.

## Relationships
`BelongsToRestaurant::restaurant()` is a `belongsTo` (`C:app/Models/Concerns/BelongsToRestaurant.php:28-30`).

## Shared entities across applications
POS tables carry their own `restaurant_id` (POS migrations); no shared constraint.

## Proposed changes
None.

## Transactions and concurrency
Not applicable.

## Indexes and query performance
Per-table `restaurant_id` indexes were not enumerated here.

## PostgreSQL vs SQLite differences
Not established.

## Migration and rollback plan
None.

## Backup/data access constraints
Tenant data is customer data; no backup read.

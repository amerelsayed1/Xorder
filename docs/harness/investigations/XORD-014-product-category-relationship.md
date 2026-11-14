# XORD-014 — Product–category relationship (POS + cloud)

Investigated 2026-10-25 by `/bug-investigation`. Sources: cloud `main 06bc8e3`, POS `main 2e7e612`, both with uncommitted work from other items (not mine). Findings are from reading source, migrations and tests plus one read-only query of the **local dev** SQLite file. No production data, no `db-backups/`, no migration run, no PostgreSQL touched.

## Headline

The ticket's premise ("missing product–category relationship") is **false for both databases**: each product has exactly one category, enforced by a NOT NULL foreign key. What the investigation did find:

1. One real cloud defect (fixed, test-first): the item create/update validators accepted a **soft-deleted** category, so a live item could be parked under a deleted category.
2. The two databases enforce the same relationship but with **different delete actions** (cloud CASCADE, POS RESTRICT). That difference is what XORD-012/013 will trip over.
3. Two facts XORD-012/013 depend on, neither of which the ticket assumed: the POS has **no tombstone/delta sync in use** (the whole catalogue is replaced on every bootstrap), and **permanent deletion of a POS product is blocked by RESTRICT** once it has stock history or sits in a combo.

## The seven required checks

| # | Question | Answer | Evidence |
| --- | --- | --- | --- |
| 1 | Category reference on `pos_products`? | **Yes.** `category_id bigint NOT NULL`. Cloud `menu_items.category_id` likewise NOT NULL. | `apps/xorder-pos/lib/data/postgres/migrations.dart:225-243`; `apps/xorder-cloud/apps/api/database/migrations/2026_06_27_002003_create_menu_items_table.php:15` |
| 2 | FK constraint? | **Yes, both.** POS: `REFERENCES pos_categories(id) ON DELETE RESTRICT` plus `pos_products_category_idx`. Cloud: `constrained()->cascadeOnDelete()` plus a `category_id` index. | same files; `…/2026_08_08_000100_add_missing_foreign_key_indexes.php:71` |
| 3 | Junction table (many-to-many)? | **No** for product→category (strictly one-to-many). Junctions exist only for *option groups* (`pos_modifier_group_categories`, cloud `option_group_category`, `menu_item_option_group`, `pos_product_modifier_groups`). So "products shared between categories" does not exist and the XORD-013 shared-product clause is moot. | `migrations.dart:4143`, `2026_08_01_000100_add_apply_scope_to_option_groups_table.php:28` |
| 4 | Association in code but not enforced by the DB? | Two soft spots. (a) Cloud soft-delete: the DB FK never fires because categories/items soft-delete; integrity there is application code only (`CategoryController::destroy` soft-deletes children in a transaction). (b) The validators did not exclude soft-deleted categories — **defect, fixed below**. No other code-only association found for products. | `Dashboard/CategoryController.php:136-141`, `Requests/Dashboard/StoreMenuItemRequest.php`, `UpdateMenuItemRequest.php` |
| 5 | Compatible structures? | **Same shape, different deletion semantics.** Both: one NOT NULL category per product. Differences: cloud ids are bigint, bootstrap writes them **verbatim** into POS (`bootstrap_seeder.dart` header comment), so ids match. POS category delete = RESTRICT; cloud = CASCADE (never fires today, soft-delete). POS adds `pos_products_sku_unique`/barcode index the cloud lacks (cloud sends `sku`/`barcode` as `null`). | `PosBootstrapService.php:236,249-266` |
| 6 | Does sync preserve the relationship? | **Yes on the happy path; one silent hole.** Bundle carries `category_id` per item and the full category list; the seeder deletes and re-inserts the whole catalogue in one transaction, so FKs hold. The hole: a product whose category is not in the bundle is **dropped silently** (no log, no report, no test) — and the orphan defect in (1) was exactly how such a product reached the bundle. | `apps/xorder-pos/lib/data/cloud/bootstrap_seeder.dart:520,610-616`; `PosBootstrapService.php:197-201` (items query is not filtered by category liveness) |
| 7 | Existing orphans? | **Local dev DB: none** (read-only query below). **Production: not checked and must not be by me** — owner to run the queries in the next section. Offline POS installs: not checked (no access); queries given. | below |

### Local dev database (read-only, `database/database.sqlite`, dev data only)
`categories 4 (0 soft-deleted) · menu_items 13 (0 soft-deleted) · items with no category row 0 · LIVE items under a soft-deleted category 0 · items whose category belongs to another restaurant 0 · order_items 4, of which 3 have NULL menu_item_id`. The 3 NULLs are lines that never carried an id (public WhatsApp path), which the schema allows.

## Defect fixed: item under a deleted category (cloud)

- **Cause:** `Rule::exists('categories','id')->where('restaurant_id', …)` does not skip soft-deleted rows. `StoreMenuItemRequest` and `UpdateMenuItemRequest` therefore accepted a deleted category.
- **Effect:** a live `menu_items` row under a deleted category. Hidden in the dashboard, still returned by `PosBootstrapService::catalog()` (items are not filtered by category), then silently dropped by the POS seeder — an item the owner believes is on the menu and a cashier never sees. Confidence: high (reproduced; HTTP 201 before the fix).
- **Fix (3 lines + comment):** `->whereNull('deleted_at')` on both rules.
- **Test:** `tests/Feature/CategoryAndItemTest.php::test_an_item_cannot_be_created_in_or_moved_to_a_deleted_category` (store and update both 422 on `category_id`, nothing written, category unchanged). Written first and seen failing (`Expected 422, received 201`), then passing.
- **Not fixed, queued:** the same `Rule::exists('categories',…)` pattern in `StoreOptionGroupRequest`/`UpdateOptionGroupRequest` (`category_ids.*`) and `StoreTaxRuleRequest` (no existence rule at all) accepts deleted categories too. Lower impact (links to a category nothing is sold from) and outside this ticket's scope; not changed.
- **Existing bad rows:** the defect has been live, so production may already hold such items. Use query B below; **no backfill was written** (data change on tenant rows needs an approved plan).

## What XORD-012 / XORD-013 will run into (verified, for the plan)

**Sales history is safe to decouple — by design, on both sides.**
- POS: `pos_order_lines.menu_item_id` has **no FK** and the line stores `name_snapshot`, `unit_price_minor`, `line_total_minor`; combo components in `pos_order_line_items` do the same. POS reports group on the line snapshot, with no join to `pos_products` (`postgres_reports_repository.dart:373-384`). Refund lines point at `pos_order_lines`, not products.
- Cloud: `order_items.menu_item_id` is nullable `nullOnDelete` (migration `2026_09_02_000100`, its own comment says a force-delete must degrade to the name snapshot); `name`/`name_ar`/`name_en` are frozen on the line; `ReportService` keys products by that name, not by id. `PosPricingEngine` already accepts a line whose item is missing or trashed (`withTrashed`, then `price_source = client_asserted` from the till's snapshot), so **an offline sale of a since-deleted item is honoured, not rejected** (`PosPricingEngine.php:62,82-100`). The one loss on a hard delete: that line's `menu_item_id` becomes NULL, so any report grouped by id rather than name loses the link (only name-keyed reports exist today).

**What a physical delete actually hits.**

| Table | On product delete | Consequence |
| --- | --- | --- |
| POS `pos_stock_movements.product_id` | RESTRICT | A product with any stock history **cannot** be deleted. The plan needs a refusal message, or an explicit decision to keep archive for stocked items. |
| POS `pos_combo_options.product_id` | RESTRICT | Product in a combo cannot be deleted until removed from it (intentional per its comment). |
| POS `pos_stock_levels`, `pos_product_prices`, `pos_product_modifier_groups` | CASCADE | Removed with the product. |
| POS `pos_categories` ← `pos_products` | RESTRICT | Category delete needs the products removed first, in one transaction. Matches the ticket's recommended app-level transaction. |
| Cloud `combo_group_items.menu_item_id` | **CASCADE** | A cloud hard delete **silently shrinks combos** — opposite of the POS rule. Needs the same RESTRICT-or-refuse treatment, or an owner decision. |
| Cloud `option_groups`/`menu_item_option_group` | CASCADE | Inline groups go with the item; fine. |
| Cloud `stock_items.menu_item_id` | nullOnDelete | Stock row survives unlinked. |
| Cloud `tax_rules` `applies_to.item_ids/category_ids` (JSON) | no FK | Dangling ids after delete. **UNVERIFIED** how `PosPricingEngine` treats an id that no longer exists. |

**Sync facts that change the design.**
- Catalogue flows **cloud → POS only.** Nothing in `lib/data/cloud` pushes categories or products upstream, and local menu authoring is disabled on cloud tills (`providers.dart` gate; `admin_repositories.dart` comment). So "locally deleted products must reach the cloud" applies to **no existing install**: an offline install has no cloud, a cloud till has no local authoring. If the owner wants offline→cloud catalogue sync, that is a new feature, not part of XORD-012/013.
- **Deletion propagation to cloud tills already works, implicitly:** every bootstrap replaces the whole local catalogue, and the cloud bundle simply omits soft-deleted rows. `deleted_ids` is always `[]` and `complete` is `true` (`PosBootstrapService.php:262-263`). POS-BE-012 (`?updated_since`, tombstones) is **APPROVED, not READY**, and the POS client does not call it. A tombstone table is therefore *not required* for correctness today; it would only be needed if delta sync is built. Recommendation: don't build one for XORD-012.
- "Other synchronized POS devices" on an offline install share **one** PostgreSQL on the branch server, so one DELETE applies to every till at once. No per-device propagation exists to design.
- "Stale offline data recreating a deleted item": the only writer of catalogue rows on a cloud till is the bootstrap seeder, which replaces from the cloud's current state. A stale till cannot resurrect an item; it will merely keep selling it until its next bootstrap, and the cloud will then price that sale from the snapshot (above).
- Cloud soft-delete is the only current "delete" for items/categories (`MenuItemController::destroy`, `CategoryController::destroy` and `bulkDestroy`); the models use `SoftDeletes`, and there is no restore route and no `forceDelete` anywhere in `app/`. Requirement "do not substitute is_deleted" therefore means **introducing** `forceDelete`, i.e. the current cloud behaviour is exactly the one the updated ticket rejects.

## Acceptance criteria for XORD-014 — status

| Criterion | Status |
| --- | --- |
| Relationships correctly defined in both databases | **Met already** (schema above). No schema change proposed. |
| Referential integrity enforced | **Met** at the DB on POS; on cloud by FK plus app-level soft-delete cascade. The cloud validator hole is **fixed**. |
| Existing valid associations preserved | **Met** — no migration written. |
| Orphans identified and handled safely | Identified in dev (none); **production/offline unchecked — owner to run queries A–C**. Handling for any found rows is not written (needs approval). |
| Sync preserves category references | **Met** for valid data; the seeder's silent drop of an orphan product is a visibility gap (queued, not changed). |
| Migrations tested against existing installations | **N/A — no migration proposed.** Required later for XORD-012/013 if schema changes. |

## Read-only queries for the owner (production cloud and each offline POS)

Run only against the real databases yourself, or against a restored copy you are authorised to use. All are SELECT-only.

```sql
-- A (cloud, PostgreSQL): live items whose category is soft-deleted or missing
SELECT i.id, i.restaurant_id, i.category_id, i.name_en
FROM menu_items i LEFT JOIN categories c ON c.id = i.category_id
WHERE i.deleted_at IS NULL AND (c.id IS NULL OR c.deleted_at IS NOT NULL);

-- B (cloud): item and category in different restaurants (tenant-boundary breach)
SELECT i.id, i.restaurant_id, c.restaurant_id AS category_restaurant
FROM menu_items i JOIN categories c ON c.id = i.category_id
WHERE c.restaurant_id <> i.restaurant_id;

-- C (offline POS): the FK forbids this, so a row here means the constraint is missing/disabled
SELECT p.id, p.category_id FROM pos_products p
LEFT JOIN pos_categories c ON c.id = p.category_id WHERE c.id IS NULL;
-- C2 (offline POS): confirm the constraint exists on the installed schema
SELECT conname, confdeltype FROM pg_constraint
WHERE conrelid = 'pos_products'::regclass AND contype = 'f';   -- expect category_id → 'r' (RESTRICT)
```

## Commands run (real output)

| Command | Result |
| --- | --- |
| `php artisan test --filter=test_an_item_cannot_be_created_in_or_moved_to_a_deleted_category` (before fix) | **failed**: `Expected response status code [422] but received 201.` |
| `php artisan test --filter=CategoryAndItemTest` (after fix) | passed, 22 tests, 71 assertions |
| `php artisan test` (full cloud suite, SQLite `:memory:`, after fix) | passed, **1090 tests, 5225 assertions** |
| read-only `sqlite3` counts on the dev file | see "Local dev database" |
| `python3 -I scripts/harness/check-citations.py` (before my doc edits) | 605 line citations resolve, 0 problems |

No pre-fix full-suite baseline was captured; the suite was green after the change, so no regression to explain.

## Not done, deliberately

- No POS code changed, and no POS test run: the POS PostgreSQL suites need a database, and `.claude/rules/postgres-migrations.md` allows that only against a disposable local database **with your consent**. A server is accepting connections on this machine at `/tmp:5432`; I did not connect to it. To verify the POS side yourself: `cd apps/xorder-pos && flutter test test/data/cloud_bootstrap_test.dart` with `POS_PG_*` pointing at a throwaway server.
- No migration, no data backfill, no commit, no push. The cloud checkout already holds many uncommitted changes from other items; this item's edits are `Requests/Dashboard/StoreMenuItemRequest.php`, `UpdateMenuItemRequest.php` and `tests/Feature/CategoryAndItemTest.php`, and `StoreMenuItemRequest.php` also carries someone else's uncommitted edits, so review the diff before committing.
- The "all skills should update harness after finish" line was read as: update the knowledge layer for this work (done here and in `docs/DOCUMENTATION_PROGRESS.md`). **I did not edit any skill definition.** If you meant "change every skill so that it always ends with a harness update", say so and I will propose the wording per skill; several already do (`/develop-feature`, `/bug-investigation` step 7).
- No full `menu-categories` / `menu-items` feature folders: the check requires seven files per folder and a partial set would fail `check-docs.py`. Queued in the progress file.

## Risks

- **Venue models:** the delete work matters most for cafés and food trucks (offline tills keep selling an item for the length of the outage; sale is honoured from the snapshot) and restaurants (combos). Cloud kitchens are unaffected beyond the combo CASCADE.
- Cloud CASCADE on `combo_group_items` + a new `forceDelete` = silent combo shrinkage in production. Highest-risk item for XORD-012.
- Hard delete removes the only link between a historical cloud line and the menu item (`menu_item_id` → NULL). Acceptable if reports stay name-keyed; a risk if anyone adds id-based product reports.
- Production may contain the orphan items from the fixed defect (unchecked).

## Next action — proposed order and approval gates

The ticket's order (XORD-014 → 012 → 013) stands, but 014 ends as "no schema change needed", so 012 can start from this report. Before any code, I need your decisions:

1. **Cloud combos:** when a deleted item is in a combo, refuse the delete (matches POS) or remove it from the combo? (Recommend refuse, with the combo names in the message.)
2. **POS stocked products:** refuse deletion when stock history exists (RESTRICT today), or keep archive for those? (Recommend refuse; history cannot be erased.)
3. **Cloud deletion mechanism:** `forceDelete` inside a transaction, after pre-checks, with an `AuditLogger` row. How `max_categories` counting and the partial unique name indexes behave once rows are really deleted is **UNVERIFIED** and must be checked in the plan. This is order-integrity-adjacent, so it needs your approval before implementation; the cloud change ships by `main` push, gated by `/release-check`.
4. Rollout: cloud first (bootstrap omits the rows), POS after, since nothing in the POS depends on cloud deletion. No contract change is needed because deletion rides on the existing full-replace bootstrap.

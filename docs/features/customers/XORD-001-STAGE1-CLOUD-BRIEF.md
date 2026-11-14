# Brief for a cloud session: XORD-001 stage 1 (cloud customer check)

Paste everything below the line into **New session → Cloud**, repository `amerelsayed1/Xorder-Menu` (the `origin` of `apps/xorder-cloud`). Plan and reasoning: `XORD-001-PLAN.md` in this folder.

---

TASK (cloud repo only, no migration, no schema change): make the POS order endpoint verify that the `customer_id` on an order belongs to the till's own restaurant.

Context: XOrder is a restaurant POS platform: a Laravel API (apps/api in this monorepo) plus a Flutter desktop POS in a separate repo. XORD-001 lets a cashier attach a customer to a POS order. The POS will start sending the order's customer to the cloud (stage 2, done separately, later). Stage 1, this task, is the cloud-side safety check that must be deployed BEFORE any POS build sends the field. Owner decisions: an order that has a customer always travels with that customer (the till uploads the customer first, then the order with the platform's customer id); a walk-in order has no customer and must keep working.

READ FIRST: this repo's CLAUDE.md and .claude/ rules; follow them. Pushes to `main` AUTO-DEPLOY TO PRODUCTION and run migrations, so: work on a new branch (e.g. `xord-001-order-customer-check`), push that branch and open a PR for review, but NEVER push to, merge into, or tag `main`, and never deploy. Do not run migrate / migrate:fresh / rollback or touch db-backups.

VERIFIED FACTS (commit 06bc8e3, origin/main):
- `apps/api/app/Http/Requests/Pos/StorePosOrderRequest.php:29` accepts `'customer_id' => ['nullable','integer']` with no existence or ownership rule.
- `apps/api/app/Services/PosOrderService.php:180` stores `'customer_id' => $data['customer_id'] ?? null` with no check. No POS build sends the field today, so the gap is dormant; it becomes live once the POS sends it.
- `CUSTOMER_NOT_FOUND` (HTTP 422, "order references an unknown customer") is listed in `docs/coordination/BACKEND_TO_POS.md` (~line 1706) but implemented nowhere: `grep -rn CUSTOMER_NOT_FOUND app tests` finds nothing. No test under `tests/Feature/Pos` names `customer_id`.
- `customer_id` is NOT part of the idempotency hash (`PosOrderService::orderPayloadHash`, ~lines 537-558), so an order first stored without a customer and replayed WITH one is not a payload mismatch. Keep it out of the hash.
- `App\Models\Customer` uses the `BelongsToRestaurant` trait. A device-token POS request has a terminal, not a logged-in user, so DO NOT assume the tenant global scope is active: verify how it resolves in this request context and scope the lookup explicitly to `$terminal->restaurant_id`.
- Other tenant errors in this service use `PosApiException` (e.g. `'BRANCH_NOT_IN_TENANT', 404` at ~line 66); mirror that with `PosApiException('CUSTOMER_NOT_FOUND', 422)`.

CHANGE:
1. When `customer_id` is present, look it up scoped to the terminal's restaurant. Found: proceed and store as today. Not found, whether it belongs to another restaurant or does not exist: throw `PosApiException('CUSTOMER_NOT_FOUND', 422)` and save nothing (the check runs before anything is written). The two cases must be indistinguishable to the caller.
2. `customer_id` null or absent (walk-in): unchanged.
3. Put the check AFTER the existing replay short-circuit (the `payload_hash` lookup near lines 48-56), so a replay of an already-stored order still returns the stored order and never becomes a 422.

TESTS (extend `tests/Feature/Pos/PosOrdersTest.php`, using the existing `PosTestCase` helpers; follow neighbouring tests): (a) own restaurant's customer accepted and stored; (b) another restaurant's customer refused with 422 CUSTOMER_NOT_FOUND and no order row written; (c) non-existent id refused the same way; (d) no customer still works; (e) a replay of an order first stored without a customer, resent with one, is not IDEMPOTENCY_PAYLOAD_MISMATCH and returns the stored order. Show the new tests fail without the change and pass with it.

RUN: `cd apps/api && php -d memory_limit=1G vendor/bin/phpunit --filter PosOrders`, then the whole `tests/Feature/Pos` folder, then the full suite `php -d memory_limit=1G vendor/bin/phpunit` (plain `php artisan test` runs out of the default 128 MB; an environment limit, not a failure). Report exact commands and real output; never say "passed" for anything not run.

DOCS: add a short note to `docs/coordination/BACKEND_TO_POS.md` in this repo saying CUSTOMER_NOT_FOUND is now enforced on the POS order endpoint. Do not edit the POS repo's copy.

DONE WHEN: branch pushed, PR open (not merged), real test output in the PR description, a list of changed files, and a short risk note: tests run on SQLite so no PostgreSQL behaviour is proved; the only behaviour change is the new 422 for an invalid `customer_id`, which no current POS build triggers. Out of scope: any POS/Flutter code, the order payload shape, migrations, XORD-005, XORD-022. Rollout: must be deployed before the POS stage-2 build ships; old POS builds are unaffected because they omit the field.

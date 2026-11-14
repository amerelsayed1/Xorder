# Cross-application analysis (cloud ↔ Flutter POS)

Run during `scan` (platform level) and re-run per feature for shared features. Output goes to the *Cross-application* section of `docs/PROJECT_OVERVIEW.md`, the footprint column of `FEATURE_INVENTORY.md`, and each feature's *Cross-application dependencies* sections. Treat both apps as independently deployed: neither ships on the other's schedule.

## 1. Consumed API surface
1. List every call the POS makes: search `apps/xorder-pos/lib/data/cloud/` (`cloud_api.dart`, `cloud_sync.dart`, `outbox_drain.dart`, `branch_sales_api.dart`, provisioning, `device_token_vault.dart`) and any other `dio`/HTTP use in `apps/xorder-pos/lib` and `bin/`. Record method, path, auth, request/response models, retry and error handling.
2. For each call find the cloud route (`routes/api.php`, mostly the `Pos` controllers behind `PosDeviceAuth`), its middleware, service and tests (`tests/Feature/Pos`). An unmatched call is a finding, in either direction (POS calls a missing route; cloud POS route that nothing calls).
3. Note the base URL / prefix handling (the API has no `/v1` prefix; versioning is by the coordination docs).
4. Include the Vue apps' consumption too (`packages/api-client`, `apps/menu/src/api.js`) for entities shared with POS (menu, orders, customers).

## 2. Contract ledger
Read `docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND,BACKOFFICE_TO_CLOUD}.md` in **both** repos (and the `docs/coordination/REVISION_*` notes). Record per item: ID, status (`READY`, `APPROVED`, `PROPOSED`...), owner. The repos hold copies that can drift: compare them with `diff` (read-only). Do not run `scripts/sync-coordination.sh` unless you have read it and confirmed the mode you use writes nothing. Document only `READY`/implemented behavior as fact; everything else as proposed.

## 3. Shared entities and models
Build a table of entities that exist on both sides: cloud model (`app/Models`) ↔ cloud table (migrations) ↔ POS domain model (`lib/domain/models`) ↔ POS table (`lib/data/postgres/migrations.dart`) ↔ wire shape (Resource / `bootstrap_bundle.dart` / `cloud_api.dart` DTOs). For each: identifiers (cloud id vs POS local id vs idempotency key), field mapping, type differences (money in decimals vs integer minor units, timestamps and time zones, enums as strings vs ints), and who is the source of truth.

## 4. Authentication and authorization boundaries
- Cloud users: stateless JWT guard (`app/Support/Jwt.php`), platform roles/`Capability` vs tenant `TenantCapability`, `RestaurantScope` tenancy, plan `Feature` entitlements.
- POS device: pairing code → device token (`PosPairingCode`, `PosTerminal`, `PosDeviceAuth`), Ed25519 offline licence (`LicenceIssuer/Activator`, `bin/pos_licence.dart`), cashier PIN (PBKDF2, `PosPin`).
- POS user permissions (`permission_resolver.dart`) versus cloud role permissions: are they the same source, copied at bootstrap, or independent? State which, with evidence.
Document where each decision is enforced (server vs client) and flag any rule enforced only on the client.

## 5. Synchronization and consistency
For every flow that crosses the boundary (bootstrap/config down, orders/shifts/refunds/customers up, licences, config version): direction, trigger (manual, timer, on-event), transport (sync vs outbox), batching, ordering guarantees, **idempotency** (key and where deduplicated), conflict resolution, retry/backoff, behavior when the cloud is unreachable, behavior when the branch database is unreachable, and what the user sees. Conclude, with evidence, whether the POS can sell without the cloud and without the branch server; do not assume "offline-first" from naming. Record eventual-consistency windows and failure modes (duplicate order, lost refund, stale price).

## 6. Business behavior differences
Compare for each shared feature: price, discount, tax and service charge calculation (POS `ticket_engine.dart` vs cloud `PosPricingEngine`), rounding rule, order state transitions (`OrderStatus` vs POS states), refund rules (`PosRefundService` vs `refund_engine.dart`), stock and purchasing, reporting definitions. The backend is authoritative for prices, discounts, taxes, totals, permissions and order transitions: flag any rule where the POS computes independently and what reconciles it.

## 7. Dependencies and rollout
- Which POS features need which cloud endpoints, config versions or licences, and the reverse (cloud features that only matter when a terminal is paired).
- Compatibility: additive vs breaking contract changes, minimum POS version supported by the cloud, data the cloud keeps for old POS clients.
- Deployment independence: cloud `main` auto-deploys to production with `migrate --force`; POS ships as an installer. Note the rollout order any documented feature depends on.

## 8. Output
A matrix of *shared feature × (cloud entry, POS entry, endpoints, shared tables/models, auth, sync mode, differences, contract IDs and status, tests on each side, risks)* plus a list of drift between coordination copies and between docs and code. Every cell cites evidence or says UNVERIFIED.

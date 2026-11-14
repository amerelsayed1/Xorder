# Xorder platform overview

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`. Depth: **route level** (2026-10-20 scan); behavior is documented for `pos-shifts` only. This page is the entry point of the knowledge layer; it is a map, not a specification. Facts cite the file they come from; unchecked items are marked UNVERIFIED. Navigation: `docs/FEATURE_INVENTORY.md` (every module and feature), `docs/modules/` (module docs), `docs/features/<slug>/` (feature docs), `docs/architecture/` (repo map), `docs/DOCUMENTATION_PROGRESS.md` (what is documented and what is stale).

## How to use this knowledge layer
- Look features up in `docs/FEATURE_INVENTORY.md` with `grep -n -i <word>`; do not read the whole inventory or every feature doc.
- Skills call `/project-documentation context <feature> <phase>`; the procedure is `.claude/skills/project-documentation/references/knowledge-retrieval.md`.
- Documentation is a lead. Check a doc's `Verified against` revision, and re-read the code you will change.

## 1. What the platform is
Xorder is a multi-tenant restaurant platform: a QR-menu and ordering SaaS (cloud) plus a desktop point of sale (POS) that sells at the counter and reports to the cloud. Source: `apps/xorder-cloud/CLAUDE.md` and `apps/xorder-pos/CLAUDE.md` (prose; the behavior of each feature is documented only where its row in the inventory says so).

## 2. Applications and stack
Versions come from `docs/architecture/repo-map.md` (verified 2026-10-20 from manifests).
| Application | Path | Stack | Deploy |
| --- | --- | --- | --- |
| Cloud API | `apps/xorder-cloud/apps/api` | Laravel 13, PHP ^8.3, PHPUnit ^12.5; prod PostgreSQL, tests SQLite | push to `main` auto-deploys to xorder.io and runs `migrate --force` (see `.claude/rules/production-safety.md`) |
| Dashboard SPA (Super Admin and restaurant) | `apps/xorder-cloud/apps/web` | Vue 3, Vite 8, pnpm/Turborepo | with the cloud |
| Marketing site | `apps/xorder-cloud/apps/landing` | Vue 3 | with the cloud |
| Diner ordering SPA | `apps/xorder-cloud/apps/menu` | Vue 3 | with the cloud |
| Shared packages | `apps/xorder-cloud/packages/{ui,api-client,analytics}` | Vue/JS | with the cloud |
| Desktop POS | `apps/xorder-pos` | Flutter 3.47 / Dart, Riverpod, go_router, direct PostgreSQL on the branch server, dio cloud client | Windows installer, started manually |
Workspace root `docs/`, `.claude/` and `scripts/harness/` are not part of either repo; the root is not a git repository.

## 3. Architecture
### Cloud
Routes `apps/xorder-cloud/apps/api/routes/{api,web,console}.php` → middleware → thin controllers under `app/Http/Controllers/{Auth,Admin,Dashboard,Pos,Public}` → `app/Http/Requests` → `app/Services` → `app/Models` (tenant scope `app/Models/Scopes`, trait `BelongsToRestaurant`) → `app/Http/Resources`. Background work is scheduled artisan commands (`routes/console.php`, `app/Console/Commands`), not queued jobs.
### Desktop POS
`lib/` layers `core → domain → data → features`; the one place implementations are chosen is `lib/app/providers.dart`; routing `lib/app/router.dart`; money and ticket rules are in `lib/domain/services/ticket_engine.dart`; persistence is `lib/data/postgres/*` (schema in `migrations.dart`); the cloud client and outbox are `lib/data/cloud/*`.
### Documented vs actual
| Prose says | Where | Code shows | Evidence |
| --- | --- | --- | --- |
| Authorization uses `Policies/` | `apps/xorder-cloud/CLAUDE.md`, previously `.claude/rules/cloud-laravel-vue.md` | No Policies directory or `->authorize()` calls; `Gate::define` in the service provider plus capability checks | `apps/xorder-cloud/apps/api/app/Providers/AppServiceProvider.php:120-163`; `ls app/Policies` fails |
| Auth is Sanctum | `apps/xorder-cloud/README.md`, `ARCHITECTURE.md` (stated stale by the repo `CLAUDE.md`) | Custom `jwt` guard | `AppServiceProvider.php:219` (`Auth::viaRequest('jwt'`) |

## 4. Authentication, authorization and tenancy
| Actor | Mechanism | Enforced at | Evidence |
| --- | --- | --- | --- |
| Platform and restaurant users | stateless JWT bearer, guard `jwt` | `auth:jwt` middleware | `AppServiceProvider.php:219`, `app/Support/Jwt.php` |
| Super Admin | `Gate::before` returns true for `SUPER_ADMIN` | gate layer | `AppServiceProvider.php:120` |
| Restaurant staff | tenant capabilities from the user's role | `can:` middleware and service checks | `app/Enums/TenantCapability.php` |
| POS terminal | device token | middleware alias `pos.device` | `apps/xorder-cloud/apps/api/bootstrap/app.php:63`, `routes/api.php:787` |
| POS cashier | local PIN and local permissions; cloud checks `acting_user_id` capability when sent | POS `Authorization`; cloud services | `apps/xorder-pos/lib/domain/services/authorization.dart`; `app/Services/PosShiftService.php:318-341` |
| Tenant isolation | global scope via `BelongsToRestaurant`; restaurant taken from the user or terminal, not the request | models, services | `app/Models/PosShift.php:18`; full audit of the pattern is pending the first `scan` |

## 5. Cross-application analysis
Depth: route level for all features (routes, POS client calls, bootstrap contents); only `pos-shifts` is traced end to end.
### POS routes served by the cloud (device-authenticated group, verified for the shift routes only)
`apps/xorder-cloud/apps/api/routes/api.php:759-818` defines the POS tiers: `pos/terminals/claim` (unauthenticated, pairing code), `pos/terminals/register` (staff JWT with `pos.provision`), `pos/terminals/heartbeat`, and a `pos.device` group with `pos/bootstrap`, `pos/terminals/rotate-token`, `pos/orders*`, `pos/refunds*`, `pos/customers`, `pos/shifts*`, `pos/cash-movements`. `subscription.writable` is deliberately absent from these (lines 774-776). The API has no `/v1` prefix.
### POS → cloud calls (extracted 2026-10-20 from `apps/xorder-pos/lib`)
18 distinct `/api/...` paths are called by the POS: `auth/login`, `dashboard/branches`, `dashboard/pos/terminals` (GET, POST), `dashboard/pos/terminals/{id}/pairing-code`, `pos/terminals/{claim,register,heartbeat}`, `pos/bootstrap`, `pos/orders`, `pos/customers`, `pos/shifts`, `pos/shifts/{id}/close`, `pos/cash-movements`, `pos/refunds`, `pos/license/check`, `pos/licence/activate` (`lib/data/cloud/cloud_api.dart`, `lib/features/licensing/data/platform_licence_api.dart`), plus `pos/branch/sales` and `pos/branch/sales/summary` (`lib/data/cloud/branch_sales_api.dart`). 17 of the 18 resolve to routes in `docs/architecture/cloud-route-index.md`; the two `branch/sales` paths have **no cloud route**: they are contract POS-BE-029, filed and not built, and the POS code says so. Of the 20 cloud `/api/pos/*` routes, 8 have no POS client call (`licence/issuer`, `licence/current`, `terminals/rotate-token`, `orders/by-client-id`, `orders/{order}/payments`, `refunds/by-client-id`, `shifts/current`, `shifts/{shift}/report`).
### Bootstrap download (`GET /api/pos/bootstrap`, `PosBootstrapService.php:57-163`)
Keys: `terminal`, `restaurant`, `branches`, `receipt_profiles`, `tables`, `catalog`, `money` (tax rules, charges, tender types), `invoice`, `endpoints`, `pos`, `modules`, `printers`, `branding`, `staff`, `customers`, `licence`. Not in the bundle: combos, units, dining areas, stock and purchasing data.
### Shared entities
| Entity | Cloud | POS | Join identity | Differences |
| --- | --- | --- | --- | --- |
| Shift | `pos_shifts` | `pos_shifts` | `client_transaction_id` uuid | staff ids differ (`users.id` vs `pos_staff.id`); see `docs/features/pos-shifts/DATABASE.md` |
Others: pending `scan`.
### Synchronization
POS writes locally first and drains a `pos_sync_outbox` to the cloud in the order customer, shift open, order, cash movement/refund, shift close (`apps/xorder-pos/lib/data/cloud/outbox_drain.dart:276-296`), idempotent by `client_transaction_id` and the `Idempotency-Key` header (`cloud_api.dart:251`). What the till does when the branch database is unreachable: UNVERIFIED.
### Contract ledger
`docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND,BACKOFFICE_TO_CLOUD}.md` exist in both repos; the copies differ (see `docs/architecture/repo-map.md`). POS-BE-009 is READY in both copies of `BACKEND_TO_POS.md` (line 203).

## 6. Modules
See the table in `docs/FEATURE_INVENTORY.md` (16 modules, 65 features, 9 drafted); footprints and route counts are in `docs/architecture/feature-route-map.md`.

## 7. Data stores
| Store | Used by | Technology | Schema source |
| --- | --- | --- | --- |
| Cloud database | cloud API | PostgreSQL (prod), SQLite (tests and dev) | `apps/xorder-cloud/apps/api/database/migrations` (111 files) |
| Branch database | POS | PostgreSQL on the branch server | `apps/xorder-pos/lib/data/postgres/migrations.dart` |
Postgres-only behavior is not covered by the cloud test suite.

## 8. Test landscape (from reports, not re-run for this page)
| Suite | Location | Result | Source |
| --- | --- | --- | --- |
| Cloud API | `apps/xorder-cloud/apps/api/tests/{Feature,Unit}` | 1024 passed, 4966 assertions | `docs/testing/reports/2026-10-20-project-test-report.md` |
| POS unit/widget | `apps/xorder-pos/test` | 2670 passed, 69 skipped (no database) | same |
| POS with PostgreSQL | `scripts/check.sh` | 3739 passed, 1 skipped | `docs/testing/reports/2026-10-20-project-test-report-pg.md` |
| Vue | none configured; `pnpm build` succeeded for 3 apps | build only | `docs/testing/reports/2026-10-20-project-test-report-build.md` |

## 9. Not found / absent
See the *Absent* table in `docs/FEATURE_INVENTORY.md`.

## 10. Unknowns and next documentation work
Run `/project-documentation scan` to deepen the inventory to route level and compute uncovered source, then `/project-documentation plan`. Highest-value first: money and order flows (`pos-orders`, `pos-refunds`, `diner-orders`), roles and tenancy, POS sync.

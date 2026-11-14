# Discovery workflow (`scan`, and the evidence step of `feature`)

Goal: an inventory of **modules** and **features** in both applications, each with verified entry points. Static reading only.

## 0. Verify the layout before trusting any description
Run and record the output; if it differs from this file, this file is stale: follow the code and note the difference.

```bash
ls apps apps/xorder-cloud apps/xorder-cloud/apps apps/xorder-cloud/packages apps/xorder-pos
git -C apps/xorder-cloud status --short; git -C apps/xorder-cloud log --oneline -1
git -C apps/xorder-pos status --short;   git -C apps/xorder-pos log --oneline -1
```
Confirm the stack from manifests, not prose: `apps/xorder-cloud/apps/api/composer.json` (framework, PHP), `apps/xorder-cloud/package.json` and each `apps/*/package.json` (Vue, Vite, pnpm, turbo), `apps/xorder-pos/pubspec.yaml` (Flutter, Dart, Riverpod, go_router, `postgres`, `dio`). Do not read lockfiles whole; `grep` a package name. Never read `.env*`.

Layout verified on 2026-10-20 (hints only, re-verify):
- Cloud: Laravel API `apps/xorder-cloud/apps/api` (`routes/{api,web,console}.php`, controllers under `app/Http/Controllers/{Auth,Admin,Dashboard,Pos,Public}`, `app/Services`, `app/Models` + `Scopes/`, `app/Enums` incl. `Capability` and `TenantCapability`, `app/Http/Middleware`, `app/Console/Commands` + `routes/console.php` scheduler, `app/Notifications`, `app/Support`). There is **no `app/Policies`** and **no queued jobs directory** at that date: authorization is `Gate` definitions in `app/Providers/AppServiceProvider.php` plus `role:`, `feature:`, `can:` and `subscription.writable` middleware; background work is scheduled artisan commands. Re-check with `grep -rl "ShouldQueue" app` and `ls app/Policies`.
- Vue: `apps/xorder-cloud/apps/web` (Super Admin under `src/pages/admin`, restaurant dashboard under `src/pages/dashboard`, `router/index.js`, `stores/`, `composables/`, `lib/capabilities.js`), `apps/landing` (marketing), `apps/menu` (diner SPA: components, composables, `api.js`), shared `packages/{ui,api-client,analytics}`.
- POS: `apps/xorder-pos/lib/{core,domain,data,features,app}`; DI in `lib/app/providers.dart`; routing `lib/app/router.dart`; persistence `lib/data/postgres/*` (direct PostgreSQL on the branch server, migrations in `migrations.dart`); cloud client `lib/data/cloud/*` (API, sync, outbox drain, provisioning); hardware `lib/data/hardware/*`; ETA e-invoicing `lib/data/eta/*`; backup `lib/data/backup/*`; features under `lib/features/*` (floor, sale, payment, receipt, refund, history, cash, lock, licensing, setup, settings, admin back office, ...); install tooling `bin/`, `installer/`, `tool/`.

## 1. Cloud discovery
1. **Routes.** Read `routes/api.php` (large; read in ranges) and `web.php`. For every route record method, path, middleware stack (including group prefixes), controller@method. Group by prefix/controller into candidate modules. Count routes so completeness can be checked later (`grep -c "Route::" routes/api.php` is only a rough count; resolve groups when listing).
2. **Backend layers per controller.** Controller → `Http/Requests` (validation) → `Services` → `Models` (note `BelongsToRestaurant` / `RestaurantScope`, casts, relations) → `Resources` → `Notifications`. Record authorization: gates in `AppServiceProvider`, `Capability` / `TenantCapability` enums, `Http/Middleware/*`.
3. **Scheduled and background work.** `routes/console.php`, `app/Console/Commands/*`, any `ShouldQueue` class, notifications and push (`PushService`).
4. **Data.** Migrations in `database/migrations` (list in order; the table creator and every later alteration), model relations, indexes and constraints. Record anything PostgreSQL-specific (raw SQL, `DB::statement`, `ilike`, partial indexes) because tests run on SQLite.
5. **Vue.** For each of `web`, `landing`, `menu`: router (guards, role/capability meta), pages, stores, composables, API calls (via `packages/api-client` or local `api.js`), i18n (AR/EN, RTL), which API endpoints each page calls. Map pages to the backend feature they drive.
6. **Integrations.** Search for outbound HTTP, mail, push, storage and map/third-party use (`Http::`, `Mail`, `Notification`, config files under `config/` read for keys' *names* only, never values).
7. **Tests.** `apps/api/tests/{Feature,Unit,Fixtures}`; Vue apps have no tests (confirm by `grep` of `package.json` scripts and `find -name "*.spec.*"`).

## 2. POS discovery
1. **Architecture.** Layers `core → domain → data → features`; where implementations are bound (`lib/app/providers.dart`); routes (`router.dart`); state (Riverpod providers, `*_providers.dart`).
2. **Features.** Each folder in `lib/features/*`: screens, widgets, controllers/application classes. Domain services (`ticket_engine.dart`, `refund_engine.dart`, `authorization.dart`, `permission_resolver.dart`, `stock_costing.dart`, `eta_*`) hold business rules: read them for rules, not the widgets.
3. **Persistence.** `lib/data/postgres/*` repositories and `migrations.dart` (the branch-server schema), `bin/pos_migrate.dart`, stored configuration (`lib/data/config`). Record local caching and the outbox (`lib/data/cloud/outbox_drain.dart`).
4. **Cloud client.** `lib/data/cloud/*`: every endpoint called, auth mechanism (device token vault), sync direction and retry behavior. **Verify** whether offline operation is real: trace what happens to a sale when the cloud or the branch database is unreachable; do not rely on the "offline-first" wording.
5. **Desktop integrations.** Printing (`lib/data/hardware`, `lib/features/receipt`), licensing (`lib/features/licensing`, `bin/pos_licence.dart`), installer (`installer/`, `tool/`), backup, ETA filing. Platform-specific code: `windows/`, `macos/`, `Platform.isWindows` branches.
6. **Errors.** Failure types and how they surface (`failure_card`, network log). **Tests:** `test/**` (unit, widget), `integration_test/`, tags in `dart_test.yaml`; count which need PostgreSQL.

## 3. Contract and cross-application step
Run `references/cross-application-analysis.md` after both sides are inventoried.

## 4. Define modules and features
- A **module** is a cohesive business area that a restaurant or platform operator would name (for example: authentication and tenancy, roles and permissions, menu management, tables and QR, ordering, POS sales and payment, shifts and cash, refunds, stock and purchasing, reports, licensing and provisioning, notifications, platform administration, landing and leads). Derive the list from the evidence; do not copy the examples.
- A **feature** is one user-visible capability inside a module, with its own routes/screens and rules. Give each a kebab-case slug unique across the platform (`<module>-<feature>` when needed). Reuse a slug if `docs/features/<slug>/` already exists.
- Mark each feature's **footprint**: `cloud-only`, `pos-only`, `shared` (both, via API), or `shared-model` (same entity, no direct API between them).
- Source not covered by any feature goes in the inventory as **uncovered** with its path; never silently drop it.

## 5. Inventory record (per feature)
Slug, module, title, footprint, cloud entry points (routes, controllers, services, pages), POS entry points (features, services, repositories), tables (cloud, POS), contract IDs and status, tests found (files), docs existing (path), status, size estimate (small/medium/large by routes + screens), unknowns. Fill `templates/FEATURE_INVENTORY.md`.

## 6. Output hygiene
Record verified paths only. Keep a list of everything you looked for and did not find (for example "no Policies directory", "no offline queue for orders"), because absence is a finding.

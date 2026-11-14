# Repo map (verified 2026-10-20 by repository inspection; xorder-pos layout re-verified 2026-11-08 on `development` `7fa0d06`)

| Workspace | Technology (verified) | Git | Notes |
| --- | --- | --- | --- |
| `apps/xorder-cloud/` | pnpm 9 + Turborepo monorepo. `apps/api` Laravel 13 (PHP ^8.3, PHPUnit ^12.5); `apps/web`, `apps/landing`, `apps/menu` Vue 3 + Vite 8; `packages/{ui,api-client,analytics}` | own repo, branch `main`, remote `amerelsayed1/Xorder-Menu` | Push to `main` auto-deploys to https://xorder.io (`.github/workflows/deploy.yml`, `deploy.sh`, `migrate --force`) |
| `apps/xorder-pos/` | Flutter 3.47 / Dart ^3.13 desktop (Windows/macOS), Riverpod, go_router, `postgres`, `dio`; Dart pub workspace: `packages/{shared_module,xorder_pos_test_support}`, `apps/{xorder_pos_offline,xorder_pos_cloud}` (verified `7fa0d06`) | own repo, remote `amerelsayed1/xorder-pos` | CI only builds the Windows installer (offline app until pos-split-apps stage 5), manually triggered |
| `docs/` | Shared harness docs: `architecture/`, `features/`, `templates/`, `harness/` | not a repo (workspace root has no `.git`) | |
| `db-backups/` | Confidential database backups | — | Never read, restore, export or delete |
| `scripts/harness/` | `verify.sh`, `check-docs.py`, `check-harness.py` | — | Safe local checks only |

## Entry points and commands
- Cloud API: `apps/xorder-cloud/apps/api` (`routes/api.php`, `routes/web.php`; thin controllers in `app/Http/Controllers/{Auth,Admin,Dashboard,Public}`, logic in `app/Services`, per-object authz in `Policies`). Run: `php artisan serve --port=8100`. Test: `cd apps/xorder-cloud/apps/api && php artisan test` (SQLite `:memory:` via `phpunit.xml`).
- Cloud web: `pnpm dev` / `pnpm build` at `apps/xorder-cloud/` root. No JS unit/E2E test framework and no `lint` scripts found in any `package.json` (the root `turbo run lint` has nothing to run).
- POS (layout verified on `development` `7fa0d06`, 2026-11-08; feature `pos-split-apps`): a Dart pub workspace. The root `pubspec.yaml` holds no code, lists the four members and owns the one `pubspec.lock`. **One codebase, two apps, one mode each.**
  - `packages/shared_module/`: the shared till, package `shared_module` (renamed from `xorder_pos` on 2026-11-08; the branch database it creates is still named `xorder_pos`). Its `lib/` layers `core → domain → data → features`; DI in `lib/app/providers.dart`; money rules in `lib/domain/services/ticket_engine.dart`; entry `lib/pos_main.dart` (`runPos(mode:, overrides:)`); `bin/pos_migrate.dart`, `bin/pos_licence.dart`, `tool/`. Declares the fonts and the mark (`assets/`) once; the apps declare none. `lib/data/cloud/` keeps only `cloud_api.dart` (licence renewal, both apps) and `device_token_vault.dart`; `lib/features/admin_mode/` is the shared Admin Mode door and the back-office contract.
  - `packages/xorder_pos_test_support/`: fakes, fonts loader, PostgreSQL fixture (`lib/pg_fixture.dart`); a dev dependency of the three other members, never a runtime dependency.
  - `apps/xorder_pos_offline/` ("XOrder POS - Offline"): `lib/main.dart`, `lib/wiring.dart` (`offlineOverrides()`), the back office `lib/features/admin/`, its tests, `windows/`, `macos/`.
  - `apps/xorder_pos_cloud/` ("XOrder POS - Cloud"): `lib/main.dart`, `lib/wiring.dart` (`cloudOverrides()`), `lib/data/cloud/` (outbox drain, `cloud_sync`, bootstrap seeder and bundle, cloud provisioning, branch sales API, logo sync), `lib/features/cloud_back_office_screen.dart` (dashboard signpost), `integration_test/`, `tool/`, its tests, `windows/`, `macos/`.
  - Boundary: the shared package imports neither app and neither app depends on the other (`packages/shared_module/test/package_boundaries_test.dart`).
  - Repo-root folders that stay: `scripts/` (`check.sh`, `package_macos.sh`, `sync-coordination.sh`), `installer/`, `docs/` (`pos/`, `coordination/`), `.github/`.
  - Test: `scripts/check.sh` from the repo root runs analyse + unit + PostgreSQL suites for every member (needs PostgreSQL); one member alone: `cd packages/shared_module && flutter test` (or the app folder). Run: `cd apps/xorder_pos_offline && flutter run -d macos` (or `apps/xorder_pos_cloud`). Windows builds and installers: CI only, started by hand; the installer builds the offline app until pos-split-apps stage 5.

## Integration surface (POS ↔ cloud)
- POS cloud client: `apps/xorder-pos/packages/shared_module/lib/data/cloud/cloud_api.dart` (HTTP client, shared by both apps) and, in the cloud app only, `apps/xorder-pos/apps/xorder_pos_cloud/lib/data/cloud/` (`cloud_sync.dart`, `outbox_drain.dart`, `branch_sales_api.dart`, `cloud_provisioning_repository.dart`, `bootstrap_seeder.dart`, `bootstrap_bundle.dart`, `logo_sync.dart`).
- Cloud POS endpoints: `apps/xorder-cloud/apps/api/routes/api.php` (POS-related services: `PosOrderService`, `PosPricingEngine`, `PosShiftService`, `PosRefundService`, `PosProvisioningService`, `PosBootstrapService`, `LicenceIssuer/Activator`). The API has no `/v1` URL prefix — contract versioning is by the coordination docs, not the URL.
- Contract ledger: `docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND,BACKOFFICE_TO_CLOUD}.md` in each repo. **The two copies of `BACKEND_TO_POS.md` currently differ**; `sync-coordination.sh` (in both repos) resolves the sibling `xorder-cloud`; `--check` currently reports drift on `POS_TO_BACKEND.md` and `BACKEND_TO_POS.md`.

## Auth and tenancy (from repo CLAUDE.md files; spot-verify before relying)
- Cloud: stateless JWT bearer guard (`app/Support/Jwt.php`), `RestaurantScope` global scope, two permission systems (`Capability`, `TenantCapability`).
- POS: Ed25519 offline licences, PBKDF2 cashier PIN.

## Existing repo-level Claude config (preserved; exposed at the root through symlinks in `.claude/agents` and `.claude/skills`)
- `apps/xorder-cloud/.claude/`: agent `xorder-cloud`, skill `release-check`, `launch.json`, `settings.local.json`.
- `apps/xorder-pos/.claude/`: agents `pos-dev`, `pos-pm`, `settings.local.json`.

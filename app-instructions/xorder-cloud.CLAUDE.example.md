# xorder-cloud scoped instructions (reference — verified 2026-10-20)

`apps/xorder-cloud/CLAUDE.md` already exists and is authoritative; this file is only a harness cross-reference. Do not copy it over the repo's own file.

- Stack: Laravel 13 / PHP 8.3 (`apps/api`), Vue 3 + Vite 8 (`apps/web`, `apps/landing`, `apps/menu`), pnpm 9 + Turborepo. Prod DB PostgreSQL; tests SQLite `:memory:` (`apps/api/phpunit.xml`).
- Tests: `cd apps/api && php artisan test` (PHPUnit 12). No JS unit/E2E framework and no PHP linter are configured.
- Auth is stateless JWT bearer (not Sanctum). Tenant isolation via `RestaurantScope`; `restaurant_id` never comes from input; cross-tenant access returns 404.
- Pushing to `main` auto-deploys to production and runs `migrate --force`: migrations must be additive and are reviewed with `/postgres-management` + `/release-check`.
- Backend is authoritative for prices, taxes and totals (`PosPricingEngine`, `PosOrderService`).

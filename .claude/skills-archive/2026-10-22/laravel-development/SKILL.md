---
name: laravel-development
description: Implement and verify Laravel API and business logic.
---

# Laravel Development

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

## Procedure
Work in `apps/xorder-cloud/apps/api` (Laravel 13, PHP ^8.3, PHPUnit 12). Read `apps/xorder-cloud/CLAUDE.md` first; it overrides older README/ARCHITECTURE prose.
- Layering: thin `Http/Controllers/{Auth,Admin,Dashboard,Public,Pos}` → `Http/Requests` → `app/Services` → `Models` → `Http/Resources` (`*PublicResource` for public-safe output); per-object authz in `Policies`.
- Auth is the custom stateless **JWT** guard (`app/Support/Jwt.php`), not Sanctum cookies. Tenant isolation is structural (`RestaurantScope` + `BelongsToRestaurant`); `restaurant_id` never comes from request input; cross-tenant access returns 404. `User` has no `RestaurantScope` — scope staff queries by hand.
- Dashboard routes stack `role:` + `feature:` + `can:` + `subscription.writable`; copy the neighbouring route group.
- Server owns prices, discounts, tax, totals and order transitions (`PosPricingEngine`, `PosOrderService`, `InvoiceSequenceService`). Order/payment endpoints must be idempotent and wrapped in transactions (see `PosOrderService` / `Http/Controllers/Pos/OrderController.php` for the existing pattern).
- Verify: `cd apps/xorder-cloud/apps/api && php artisan test --filter <Name>`, then the full suite. Tests run on SQLite `:memory:`; no PHP formatter or static analyser is configured — do not add one without approval.
- Add feature tests (happy path, validation, authorization, cross-tenant 404, idempotent retry). Never run `migrate` against a non-test database; `main` auto-deploys with `migrate --force`.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.

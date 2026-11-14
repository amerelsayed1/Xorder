# API contract: financial accounts (XORD-015, stage 1)

Verified against: xorder-cloud `06bc8e3` and xorder-pos `a6f5fe5`, **both working trees dirty** (the files below are new or edited on top of other uncommitted work) · 2026-10-26. Status of the contract: **`POS-BE-032` PROPOSED** (`BACKEND_TO_POS.md`); the POS parses and seeds the bundle keys and nothing else reads them. Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `W:` = `apps/xorder-cloud/apps/web/`, `P:` = `apps/xorder-pos/`.

## Producers and consumers
| Surface | Producer | Consumers |
| --- | --- | --- |
| `/api/dashboard/financial-accounts` (4 routes) | `C:app/Http/Controllers/Dashboard/FinancialAccountController.php` | `W:src/pages/dashboard/settings/FinancialAccountsPanel.vue` |
| `/api/dashboard/tender-account-defaults` (2 routes) | `C:app/Http/Controllers/Dashboard/TenderAccountDefaultController.php` | the same panel |
| bootstrap `money.financial_accounts`, `money.tender_account_defaults` | `C:app/Services/PosBootstrapService.php` (`money` block) | `P:lib/data/cloud/bootstrap_bundle.dart` (`BootstrapFinancialAccount`, `BootstrapTenderAccountDefault`), `bootstrap_seeder.dart` (`_seedFinancialAccounts`, `_seedTenderAccountDefaults`) |

The existing `GET/POST/PUT/DELETE /api/dashboard/tender-types` and `money.tender_types[]` are **unchanged** (asserted by `FinancialAccountsTest::test_the_bundle_carries_accounts_and_defaults_and_leaves_tender_types_as_they_were`).

## Verified endpoints
All under `Route::prefix('dashboard')` with `auth:jwt`, `role:<tenant roles>` and `feature:pos` (`C:routes/api.php:660`).

| Method | Path | Gate | Controller@method | Route |
| --- | --- | --- | --- | --- |
| GET | `/api/dashboard/financial-accounts` | `can:settings.view` | `index` | `C:routes/api.php:699` |
| GET | `/api/dashboard/tender-account-defaults` | `can:settings.view` | `index` | `:700` |
| POST | `/api/dashboard/financial-accounts` | `can:settings.view`, `can:finance.accounts`, `subscription.writable` | `store` | `:703` |
| PUT | `/api/dashboard/financial-accounts/{financialAccount}` | same | `update` | `:704` |
| DELETE | `/api/dashboard/financial-accounts/{financialAccount}` | same | `destroy` (**deactivates**) | `:705` |
| PUT | `/api/dashboard/tender-account-defaults` | same | `update` (set or clear one pair) | `:706` |

Route numbers are a snapshot of the working tree; `routes/api.php` also carries other uncommitted edits.

## Authentication and authorization
- Writes need **`finance.accounts`** (`TenantCapability::FINANCE_ACCOUNTS`), deliberately not `settings.update`: a person who may rename a payment method cannot redirect where the money lands. It **implies `settings.view`** (`TenantCapability::implies()`), because the accounts live in Settings. The restaurant owner holds every capability implicitly; a role gets it only by being given it.
- Reads need `settings.view` (the payment-method editor already needs the list).
- Tenant isolation is structural (`BelongsToRestaurant` + `RestaurantScope`): `restaurant_id` is never read from input, and an account id from another restaurant is **404** on `PUT`/`DELETE` (route-model binding through the global scope). Ids inside a body (`branch_id`, `tender_type_id`, `financial_account_id`) are validated with `Rule::exists(...)->where('restaurant_id', <caller's>)` and answer **422**.
- Writes also stack `subscription.writable` (a lapsed subscription is read-only).
- **Who can read:** anyone with `settings.view` can read the account list, including `reference_label`, and which method pays into which account. That is deliberate (the payment-method editor needs it) but widens who sees a bank hint beyond the people who edit it; the owner decides who holds `settings.view`.
- **Audit:** creating, changing, clearing or switching off an account or a default is written to the activity log (`financial_account.*`, `tender_account_default.*`). A default's line reads, for example, `Card pays into CIB main (all branches)`; the log stores the account name and reference label as they are.
- `DELETE /api/dashboard/branches/{branch}` now answers **409** (`branch_has_accounts`) while an account is tied to that branch.

## Request and response examples (redacted)
`POST /api/dashboard/financial-accounts`
```json
{ "name": "CIB main", "kind": "bank", "branch_id": null, "reference_label": "CIB 4521", "sort_order": 0 }
```
201 `{"data": {"id": 71, "restaurant_id": 3, "branch_id": null, "name": "CIB main", "kind": "bank", "currency": "EGP", "reference_label": "CIB 4521", "is_active": true, "sort_order": 0, ...}, "message": "..."}`

- `kind` is `cash | bank | wallet`. `currency` is **set by the server** from the restaurant; a `currency` in the body is ignored (`test_the_owner_adds_an_account_and_the_server_sets_the_currency`).
- `name` is trimmed and unique per restaurant **without regard to case** (the request compares `lower(name)`; the database key is exact). A concurrent duplicate is answered as a 422, not a 500.
- `reference_label` (max 40) **and `name`** are refused (422) when they contain nine or more digits in a row in any script (Arabic-Indic and full-width digits count), with up to three non-letter, non-digit characters between them. This is a **heuristic against storing an account number by accident, not a guarantee**: a number split by letters gets through. The till applies the same pattern.
- `is_active` and `sort_order` may be omitted but not `null` (422); `sort_order` is 0 to 100000.
- `DELETE` returns `{"data": <account with is_active false>, "message"}`; the row stays.
- `PUT` and `DELETE` are **refused (422, key `is_active`)** while the account is the default of any payment method; `PUT` that ties an account to a branch is refused (422, key `branch_id`) while a default points at it from another branch or from the business-wide fallback.

`PUT /api/dashboard/tender-account-defaults`
```json
{ "tender_type_id": 5, "branch_id": null, "financial_account_id": 71 }
```
200 `{"data": {"id": 9, "tender_type_id": 5, "branch_id": null, "financial_account_id": 71}, "message"}`. A null `financial_account_id` clears the pair (`{"data": null}`). One row per `(payment method, branch)`; a null branch is the business-wide fallback. A default must be an **active** account that is **shared** or **tied to that same branch**; a business-wide default must therefore be a shared account (422 on `financial_account_id` otherwise).

Bootstrap (`GET /api/pos/bootstrap`, `money` block) — see `POS-BE-032` in `BACKEND_TO_POS.md` for the shape. Inactive accounts are included so a till can switch off its copy.

## Error formats
Standard Laravel validation: 422 `{"message": "...", "errors": {"<field>": ["..."]}}`. 403 for a missing capability. 404 for another restaurant's account. The messages are localised (`lang/{en,ar}/xorder.php`, keys `validation.account_*`).

## Backward compatibility
Additive only. No existing route, request or response key changes. Older POS builds ignore the two new `money` keys (they read `tender_types` field by field and keep `money` verbatim); **not exercised on an old build** (none available here). A newer POS against an older cloud sees the keys absent and leaves its accounts alone (`financial_accounts_test` "an older platform that sends no accounts leaves the till's alone"). Rollout order: cloud, then POS.

## Contract tests
Cloud: `tests/Feature/Pos/FinancialAccountsTest.php` (24). POS: `test/data/financial_accounts_bundle_test.dart` (parsing, absent versus empty), `test/data/financial_accounts_test.dart` (seeding, PostgreSQL).

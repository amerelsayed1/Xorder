# Financial accounts — technical plan (financial-accounts, XORD-015)

Status: **stage 1 BUILT 2026-10-26 on approval (not committed, not deployed); stage 2 NOT approved and NOT built.** The plan below is kept as approved; "As built" lists where the code differs from it. Verified against: xorder-cloud 06bc8e3 and xorder-pos a6f5fe5, **both working trees dirty**.

## As built — stage 1 (2026-10-26)
Approved by the owner in chat on 2026-10-26: build stage 1, with the **mapping table** for D-1. Decisions taken while building, all inside that approval:

| # | Plan said | Built | Why |
|---|---|---|---|
| 1 | capability `finance.manage` | **`finance.accounts`** (cloud `TenantCapability::FINANCE_ACCOUNTS`, till `PosCapability.financeAccounts`) | the role builder composes a label from `capres.<resource>` + `capaction.<action>`, and `capaction.manage` is already "Manage suppliers, purchases & stock" (purchasing). `finance.manage` would have read "Finance — Manage suppliers, purchases & stock". It implies `settings.view` (a role that can manage accounts must be able to open Settings); the first test run found that without it a `finance.accounts`-only role got 403 on its own write |
| 2 | selector in `TenderTypeDialog` | selector in the **Accounts pane** (chips, per branch) and on the dashboard Accounts tab | that dialog and `management_tenders_pane.dart` already hold other sessions' uncommitted work; the pane also works read-only on a cloud till |
| 3 | partial unique index for the business-wide default | `branch_key` (non-null, 0 = whole business) + ordinary unique | `.claude/rules/cloud-laravel-vue.md`: no engine-specific SQL |
| 4 | accounts pane reads `branchesProvider` | `FinancialAccountsRepository.branches()` | the shared provider's fake carries a 120 ms timer that fails the pane-walking test; the pane now depends on one repository |
| 5 | (not planned) | a default blocks switching its account off, and retying it to another branch (cloud 422, till `AccountRefused.accountIsDefault`) | otherwise a default could point at an account that can no longer receive money |
| 6 | defaults seeded after tender types | same, and accounts **before** both | `pos_tender_account_defaults` references both; tenders are found through `platform_id` |

Gating as built: `GET financial-accounts` and `GET tender-account-defaults` need `settings.view`; every write needs `finance.accounts` (+ `subscription.writable`). Setting a default is `finance.accounts` too, never `settings.update`.

Files: cloud `database/migrations/2026_10_26_000{1,2}00_*`, `Models/{FinancialAccount,TenderAccountDefault}`, `Http/Controllers/Dashboard/{FinancialAccount,TenderAccountDefault}Controller`, `Http/Requests/Dashboard/{Store,Update}FinancialAccountRequest` + `SetTenderAccountDefaultRequest`, `Enums/TenantCapability` (+ `implies()`), `Services/{PosBootstrapService,PosConfigVersion}`, `routes/api.php`, `lang/{en,ar}/xorder.php`; web `settings/FinancialAccountsPanel.vue` (new), `PaymentMethodsView.vue`, `packages/ui/src/i18n/index.js`. POS `lib/domain/models/financial_account.dart`, `lib/domain/repositories/{repositories,admin_repositories}.dart`, `lib/data/postgres/{migrations,local_bootstrap,postgres_financial_accounts_repository,postgres_financial_accounts_admin_repository}.dart`, `lib/data/cloud/{bootstrap_bundle,bootstrap_seeder}.dart`, `lib/app/providers.dart`, `lib/domain/models/permissions.dart`, `lib/features/admin/presentation/{management_accounts_pane,financial_account_dialog,management_screen,admin_messages}.dart`, `lib/core/l10n/app_strings.dart`.

Edited on top of **other sessions' uncommitted work** (hunks added, nothing reverted): cloud `TenantCapability.php`, `PosBootstrapService.php`, `PosConfigVersion.php`, `routes/api.php`, `PaymentMethodsView.vue`, `i18n/index.js`, both `lang/*/xorder.php`, `BACKEND_TO_POS.md`; POS `app_strings.dart`, `bootstrap_bundle.dart`, `bootstrap_seeder.dart`, `migrations.dart`, `permissions.dart`, `management_screen.dart`, `local_bootstrap.dart`, `providers.dart`, `admin_messages.dart`, `BACKEND_TO_POS.md`, and the four test files named in `CHANGELOG.md`. In `providers.dart` an accidental `dart format` reflowed 14 unrelated hunks; they were identified by formatting the committed file and **restored** (the remaining diff is additions only).

Stage 2 hazards (unchanged, still to resolve in its own plan): payload hashes if an account id enters them, the drain's all-or-nothing hold, no currency source on the till, shift expected-cash by tender kind, the parked-ticket codec.

---

### Independent review — 2026-10-26 (security, database, code), and what was done
Three read-only reviewers read the diff; none found a critical or high defect. Disposition:

| Finding | Source | Disposition |
|---|---|---|
| Deleting a branch that has an account → database error (500) | security, database, code | **Fixed**: `BranchController::destroy` answers 409 `branch_has_accounts`; test `test_a_branch_that_has_an_account_cannot_be_deleted_and_says_why` (mutation-checked) |
| `is_active` / `sort_order` explicit `null` → 500 | security, code | **Fixed**: `sometimes` instead of `nullable`, `sort_order` max 100000; test |
| Account-number guard missed Arabic-Indic / full-width digits and other separators; `name` unguarded | security, code | **Fixed** both sides (`\p{Nd}`, up to 3 separators, applied to `name` and `reference_label`); tests on both sides (mutation-checked on the cloud). Documented as a **heuristic** |
| Cloud name uniqueness case-sensitive, till case-insensitive; race → 500 | security, database, code | **Fixed**: cloud compares `lower(name)`, a database race is a 422 |
| Cloud audit line for a default read `"#9" created` | code | **Fixed**: `TenderAccountDefault::auditLabel`; test reads the activity file |
| Branch-tied account unusable as a default on a one-branch business; AC-7 said "tied to the branch" but the dialog defaulted to shared | code | **Fixed by removing the trap**: the branch choice is offered only with more than one branch (or for an already-tied account); FEATURE BR-12/AC-7 reworded; tests on both sides |
| Till dialog closed on a refusal and lost the typed values; pane could stay locked if the repository threw | code | **Fixed**: dialog reopens on the draft with the reason inside; `try/finally` on `_busy`; tests |
| Vue panel: RTL toast, own modal, off-theme colours, three requests on every visit, unseen errors, stale comment | code | **Fixed**: shared `Modal`, `inset-inline` toast, theme variables, panel mounted on first open, other errors shown, comment replaced. `pnpm build` green; **not opened in a browser** |
| Over-grant: `UPDATE` on the defaults sequence | database | **Fixed** |
| Weak tests (`expect(bank.id, isNonZero)`, a read-only test named "write nothing"), missing successful-`PUT` test, bundle test ignored other tenant's defaults | code | **Fixed** (removed / added) |
| Restaurant delete may fail on PostgreSQL because the accounts' branch foreign key is NO ACTION | database | **Not reproduced**: a rolled-back temp-table repro of the same shape on PostgreSQL 16 deletes cleanly. Production's version is unverified |
| Platform ids vs locally authored ids could collide when a till changes from offline to cloud | database | **Accepted for stage 1, required before stage 2** (see `DATABASE.md`, "Known hazards") |
| `branch_key` hook can be bypassed by query-builder writes | database | **Accepted**: only the controller writes the table; documented |
| set-default vs switch-off race; unique-violation retry inside a transaction | security, database | **Accepted** (no money at stake in stage 1); documented |
| Any `settings.view` holder can read the list and `reference_label`; the bundle sends other branches' accounts to every till | security | **Accepted by design**; documented in `API.md` |
| The pane integrates `POS-BE-032`, still PROPOSED (workspace rule: integrate only READY) | code | **Open**: approved in the plan as a PROPOSED addition; the owner flips it to READY after review |
| Hard-coded `sortOrder 99` for a new account on the till; wrong "platform-managed" notice on an unconfigured offline till; no edit affordance on a row | code | **Not changed** (cosmetic) |

---

> **The sections below are the plan as approved.** Where they name `finance.manage`, `PosCapability.financeManage`, a *partial unique index*, `nullOnDelete`, or the selector in `TenderTypeDialog`, read the "As built" table above: it supersedes them.

## 0. Discrepancies found while re-reading the code (decide before building)
| # | Finding | Evidence | Consequence |
|---|---|---|---|
| D-1 | **A single default account on the payment method cannot serve a multi-branch business.** Payment methods are restaurant-wide (no branch column), but the owner wants accounts tied to branches. "Cash" in branch 1 and branch 2 cannot both default to a branch-tied drawer account with one column. FEATURE BR-3 says "at most one default" and was written without this. | `TenderType.php:15`, `create_pos_money_config_tables.php:48`, `pos_tender_types` migration 23 | Recommended: a **mapping table** (method × branch → account; branch null = restaurant-wide fallback). Alternative A: one column on the method, and a default must then be a shared (no-branch) account — simpler, but a chain cannot map cash to each branch's drawer. |
| D-2 | **The POS has no restaurant-currency source.** `pos_restaurants` has no currency column; the bundle's `currency` is parsed but never stored; amounts default to `'EGP'`. | `migrations.dart:123`, `bootstrap_bundle.dart:68`, `ticket.dart:619` | In stage 1 an account's currency is set **by the cloud from the restaurant's currency**, never typed by the user; the till shows it, does not validate against it. Currency-aware transfers (stage 2) need this solved first. |
| D-3 | **Tender kind vocabularies disagree** (cloud: cash/card/external/other; till: cash/card/wallet/account/voucher/other). | `StoreTenderTypeRequest.php:19`, `tender_method.dart:18,53` | Not touched. Account `kind` (cash/bank/wallet) is a separate word list and is named `kind` on accounts only, never tied to tender kind. |
| D-4 | **`BACKEND_TO_POS.md` differs between the two repos** and has no READY item for accounts. | `diff -q` | Contract item written as **PROPOSED** first in the cloud copy (the owner of the file) and mirrored; integrate only after it is READY. |
| D-5 | A stale comment in `management_screen.dart` (~150-156) says payment methods are "local on both deployments"; the pane and seeder say the platform authors them on cloud. | agent report | Not changed (unrelated); noted. |
| D-6 | Docs: no `docs/features/tender-types/`; inventory row `FEATURE_INVENTORY.md:56` is `pending/UNVERIFIED`. | | Reported; `/project-documentation feature tender-types` proposed as a follow-up. |

## 1. Design (stage 1)
**Cloud**
- Table `financial_accounts`: `id`, `restaurant_id` (FK, cascade), `branch_id` (nullable FK to `branches`, default NO ACTION, not set-null, so a removed branch cannot silently turn an account into a shared one), `name` (120, unique per restaurant), `kind` (`cash|bank|wallet`), `currency` (3, set server-side), `reference_label` (nullable, 40: e.g. last four digits; **no** account numbers or credentials), `is_active`, `sort_order`, timestamps.
- Table `tender_account_defaults` (recommended D-1): `id`, `restaurant_id`, `tender_type_id` (FK, cascade), `branch_id` (nullable), `financial_account_id` (FK, nullOnDelete not used: accounts are never deleted), `timestamps`; unique `(tender_type_id, branch_id)` plus a partial-unique equivalent for `branch_id IS NULL`. Effective account for method M at branch B = row(M,B) else row(M,null) else none.
- Accounts are never deleted: `DELETE` deactivates (same as tender types).
- Model `FinancialAccount` with `Auditable, BelongsToRestaurant`; added to the `PosConfigVersion` hook list (`PosConfigVersion.php:62`) so a change bumps `pos_config_version` and breaks the bundle ETag. Mapping model likewise.
- Endpoints (dashboard, inside `feature:pos`): `GET financial-accounts` (`settings.view`), `POST/PUT/DELETE financial-accounts` (`finance.manage` + `subscription.writable`), `GET/PUT tender-account-defaults` (write needs `finance.manage`; a `settings.update`-only user cannot redirect money). Responses follow the `{data, message}` shape of `TenderTypeController`; the **existing `tender-types` response is not changed**.
- Validation: `branch_id` and account ids via `Rule::exists(...)->where('restaurant_id', $tenant)`; cross-tenant ids are 404/422 as elsewhere; a default must be an active account that is shared or tied to the mapping's branch; name trimmed and unique.
- Capability `finance.manage` (two-part name, so the existing label function works; new `capres.finance` / `capaction.manage` i18n keys in both languages; `group()` gets a `finance` case). Owner holds it implicitly; it is **not** added to any other role.
- Bundle: `money.financial_accounts` and `money.tender_account_defaults` added to `PosBootstrapService` (`:117-135`); existing keys untouched.
- Web: replace the "Accounts" placeholder tab in `PaymentMethodsView.vue` with a list + add/edit/disable modal; a default-account selector per method (and per branch where the restaurant has more than one). Write controls hidden without `finance.manage`.

**POS**
- Migration **60** (next free; **56-59 are uncommitted**, so 60 is only valid while they stay): `pos_financial_accounts` (id = platform id on cloud, bigserial offline; `CREATE TABLE IF NOT EXISTS` exactly, for `grants_cover_usage_test`), `pos_tender_account_defaults`, owner role backfill `finance.manage` (as migration 59 did). No change to `pos_tender_types`, `pos_order_payments`, `pos_refund_payments`.
- Grants in `local_bootstrap.dart`: till `SELECT`; cloud-seeding block `INSERT, UPDATE` + sequence; offline `REVOKE`; admin `SELECT, INSERT, UPDATE` + sequence. No `DELETE` anywhere.
- Domain: `FinancialAccount`, `TenderAccountDefault`; read repository (till credential) and admin repository (offline only, admin credential + `finance.manage`), in **new files** to avoid the dirty `postgres_catalog_admin_repository.dart`.
- Seeder: new `_seedFinancialAccounts` **before** `_seedTenderTypes`; platform ids as primary keys (`_bumpSequences` gets the table); retire (`is_active=false`), never delete; an absent `money.financial_accounts` key leaves the table alone (older cloud); an unknown account id in a default is skipped, not fatal.
- UI: new pane `ManagementPane.financeAccounts` appended at the **end** of the enum, in `BackOfficeTab.finance`, `static const requires = {PosCapability.financeManage}`; list on cloud tills with `PlatformOwnedNotice` and no write controls (same rule as `ManagementTendersPane`; not in `_authoringPanes`); add/edit/disable on offline tills. A default-account chip/selector in `TenderTypeDialog` via an **optional** parameter (keeps `tender_types_ui_test` working). EN/AR strings in all three `AppStrings` places. **Arabic wording is my proposal and needs the owner's read.**
- Permissions: `PosCapability.financeManage = 'finance.manage'` in `all`, `backOffice`, `_risk` (high), a `CapabilityGroup`, label strings; `AuditAction.financialAccountSaved` + the hand list in `capability_labels_test.dart`.
- An offline till's accounts never leave the till (BR-12).

## 2. Stages, order, tests, rollback
Order: additive schema and producer first (cloud), consumers after (web, POS). Each stage ends with its tests run.

| Stage | Repo | Change | Tests (new unless noted) | Rollback |
|---|---|---|---|---|
| 0 | both | **Baseline**: run the existing suites before any edit, record real output (the trees are dirty, so failures may predate me) | `php artisan test`; `flutter analyze && flutter test` | n/a |
| 1a | cloud | migrations, models, `finance.manage`, hooks, controller, requests, routes | `FinancialAccountsTest`: CRUD, validation, disabled account refused as default, two-restaurant isolation (404), branch from another tenant refused, `settings.update`-only user cannot set defaults (403), owner can, audit written. `TenantRbacTest`/`UserCreationMatrixTest` re-run (iterate over `cases()`) | revert files; migrations are additive and unapplied to any real DB |
| 1b | cloud | bundle block + version bump | extend `PosDefaultTendersTest`-style: bundle carries accounts and defaults, config version bumps, ETag changes, no other tenant's rows; **tender-types response unchanged** (assert exact keys) | revert |
| 1c | cloud web | Accounts tab, selector, i18n (merge by hand into the already-modified `packages/ui/src/i18n/index.js`), capability labels | `pnpm build` (no JS test framework; stated); manual checklist | revert |
| 1d | POS | migration 60, grants, models, repos, parse, seeder | `cloud_bootstrap_test` (parse; absent key; unknown ids), `till_grants_test`, `grants_cover_usage_test`, `capability_labels_test`; integration (need `POS_PG_HOST`): `financial_accounts_test` (offline CRUD, retire-not-delete, bundle re-seed twice), owner backfill like `business_logo_test` | new migration only appends; revert files |
| 1e | POS | pane, dialog selector, strings, tab wiring | widget tests: cloud (read-only + notice), offline (add/edit/disable), cashier without `finance.manage` sees no pane, AR/RTL; update `back_office_shell_test` `_finance` list, `cloud_purchasing_hidden_test`, `settings_bar_test`, `localisation_test` | revert |
| 1f | docs | FEATURE/TECHNICAL/API/DATABASE/TEST_PLAN/TEST_REPORT/CHANGELOG; contract item; tracker | `bash scripts/harness/verify.sh` | n/a |
| 2 | both | **Not planned in detail; separate approval.** Account on each payment and refund (snapshot id + name + kind), cashier override (new permission), admin transfer, append-only movements + balance, outbox/drain and cloud ingest | design hazards below | |

**Stage 2 hazards to resolve before its plan:** payment payload hashes (`paymentPayloadHash`, `orderPayloadHash`, `PosRefundService::payloadHash`) change if an account id enters them, and an old replay would then return `IDEMPOTENCY_PAYLOAD_MISMATCH` — decide to derive the account on the cloud from the default (hashes unchanged) or version the hash; the drain's `_hold` is all-or-nothing, so a payment naming an account with no platform id would hold the whole order; there is no currency source on the till (D-2); shift expected-cash is by tender kind (`PosShiftService.php:214-284`) and must stay that way; a parked-ticket codec serialises tenders and would need the account.

## 3. Impact
- **Contracts:** additive keys in `money` (`financial_accounts`, `tender_account_defaults`); no existing key, route or response changes. The till ignores an absent block; an older till ignores unknown keys (cloud agent: UNVERIFIED that the *current* POS parser tolerates them — the parser reads per field, so likely; **a test proves it** in 1d).
- **Rollout order (written down):** 1. cloud deploy of 1a-1b (additive; no behaviour change for existing tills). 2. dashboard (1c) ships with the cloud. 3. POS release (1d-1e). Old POS + new cloud: works, accounts invisible. New POS + old cloud: absent key, works.
- **Data / migrations:** additive only; **none run on any real database by me**. The cloud migration reaches production when the owner pushes `main` (auto `migrate --force`). Cloud tests run on SQLite and cannot prove PostgreSQL behaviour: reviewed by reading — FK with default NO ACTION on branch (cascade-safe on restaurant delete), partial unique index for the null-branch default (SQLite and PostgreSQL treat NULLs in a plain unique index alike: both allow duplicates, hence the partial/explicit check), no table rewrite, no backfill.
- **Permissions:** one new capability, owner only; nothing narrowed. A custom role must be granted it explicitly.
- **Tenant isolation / money:** accounts carry no balances and nothing is posted in stage 1; `order_payments`, shifts, Z report, tax and totals are untouched.
- **Venue models:** café (cash/card/wallet accounts), restaurant (bank vs drawer), food truck (one shared account, no branch needed), cloud kitchen (a bank/wallet account to receive payouts; aggregator reconciliation stays a known gap). Nothing assumes tables, addresses or stable network.
- **Dirty trees:** I will edit files that also hold other sessions' uncommitted work: cloud `TenantCapability.php`, `PosBootstrapService.php`, `PosConfigVersion.php`, `routes/api.php`, `PaymentMethodsView.vue`, `packages/ui/src/i18n/index.js`; POS `app_strings.dart`, `bootstrap_bundle.dart`, `bootstrap_seeder.dart`, `migrations.dart`, `permissions.dart`, `management_screen.dart`, `tender_type_dialog.dart`, `local_bootstrap.dart`, `grants_cover_usage_test.dart`, `back_office_shell_test.dart`. I add hunks only, revert nothing, and my diff will be mixed with theirs in `git diff`.

## 4. Verification commands
- Cloud: `cd apps/xorder-cloud/apps/api && php artisan test --filter=FinancialAccounts` then `php artisan test`.
- Web: `cd apps/xorder-cloud && pnpm build`.
- POS: `cd apps/xorder-pos && flutter analyze && flutter test`; integration: `POS_PG_HOST=… flutter test --tags integration --concurrency=1` (reported **not run** if the server is absent).

## 5. Approvals needed
1. **Go for stage 1** (1a-1f). Stage 2 is *not* approved by this plan.
2. **D-1:** mapping table (recommended) or a single column.
3. Additive cloud and POS migrations (written, not run).
4. New capability `finance.manage` (owner only).
5. Contract addition as PROPOSED in `docs/coordination/` of both repos.
6. Editing files that carry other uncommitted work (list in section 3).
7. Any push to `xorder-cloud` `main` remains yours, after `/release-check`; I do not commit or push.

## 6. Defaults used for the still-open FEATURE questions (change any)
Override needs a permission (stage 2); refund goes to the original account (stage 2); manage under a new `finance.manage`; currency from the restaurant, not typed; late payment to a disabled account accepted and flagged (stage 2); no plan cap; no link to `pos_cash_drawers` (left untouched); `external`/`wallet` kind mismatch not touched; supplier payments/expenses out of scope.

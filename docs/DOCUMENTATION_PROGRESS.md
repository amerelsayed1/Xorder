# Documentation progress

Updated: 2026-10-20 by the harness knowledge-integration dry run (not a full `/project-documentation` command run)
Rules: `.claude/skills/project-documentation/references/progress-management.md`.

## Source baseline
| Repo | Branch | HEAD documented against | Uncommitted files at documentation time |
| --- | --- | --- | --- |
| `apps/xorder-cloud` | main | `06bc8e3` | 10 files, all docs/agent/script (`.claude/agents/xorder-cloud.md`, `CO-HOST-PREP.md`, `docs/…`, `scripts/sync-coordination.sh`); none is an evidence file of a documented feature |
| `apps/xorder-pos` | main | `d592db8` | 11 files: `CLAUDE.md`, `docs/…`, `scripts/sync-coordination.sh`, `lib/features/admin/presentation/management_screen.dart`, `test/features/cloud_purchasing_hidden_test.dart`; none is an evidence file of a documented feature |
(Current HEAD is compared at each `status` / `update` / `context` run, not stored here.)

## Summary
| Status | Features |
| --- | --- |
| pending | 55 (route-level scan only) |
| discovered | 0 |
| drafted | 10 (`tax-rules` (partial scope, 2026-10-26), `pos-shifts`, and batch 1: `auth-login`, `auth-password-reset`, `auth-signup`, `tenant-isolation`, `staff-management`, `tenant-roles`, `platform-users`, `pos-pin`) |
| validated | 0 |
| stale | 0 |
| blocked | 0 |
| removed | 0 |

## Plan
Prepared 2026-10-20 after the route-level scan (cloud `main 06bc8e3`, POS `main d592db8`). Counts at plan time: 64 features in 16 modules (65 after batch 1 added `tenant-isolation`); batch 1 (auth-and-tenancy, roles-and-staff) is documented, see the run log.

**Policy for this plan** (from the `pos-shifts` experience, nine independent passes): every feature gets the `feature` procedure (core files plus `BEHAVIORAL_ANALYSIS.md` for traced conclusions), the mechanical checks (`scripts/harness/check-citations.py`, `check-docs.py`) and an author self-check, which yields `drafted`. Independent validation passes (about 200-330k subagent tokens each, measured) are reserved for **P0 features** (money, order state, permissions/tenancy, sync/licensing). Everything else stays `drafted` with its UNVERIFIED list and the freshness/spot-check protocol of `knowledge-retrieval.md`. Rough effort per documented feature is an estimate (2-3 analyst sweeps plus writing, order of 150-250k tokens); documenting all 63 would be in the order of 10M tokens before validation, so the batches below are meant to be run one at a time with a stop after each.

**P0 features (17):** `auth-login`, `tenant-roles`, `staff-management`, `pos-orders`, `pos-payment`, `pos-refunds`, `tax-rules`, `service-charges`, `tender-types`, `pos-terminals-pairing`, `pos-bootstrap`, `pos-licensing`, `pos-cloud-sync`, `diner-orders`, `order-status-workflow`, `dashboard-orders`, `supplier-invoices-payments`.

| Batch | Modules | Features | P0 in batch | Agents | Contract / schema work | Human questions or blockers |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | auth-and-tenancy, roles-and-staff | 7 | `auth-login`, `tenant-roles`, `staff-management` | `feature-analyst` x2, `security-reviewer` (tenancy, JWT, capabilities) | none | open question 4 (POS staff id vs cloud user id) |
| 2 | pos-sales + `pos-refunds` | 6 | `pos-orders`, `pos-payment`, `pos-refunds` | `feature-analyst` x3 (cloud order service, POS ticket engine, refunds), `api-contracts` | POS-BE-006/007/010 | decide whether the POS ticket engine's tax rules and the cloud pricing engine must be compared line by line |
| 3 | pricing-tax-tenders | 5 | `tax-rules`, `service-charges`, `tender-types` | `feature-analyst` x2, `database-reviewer` | bootstrap `money` block | none known |
| 4 | pos-provisioning-licensing | 5 | `pos-terminals-pairing`, `pos-bootstrap`, `pos-licensing`, `pos-cloud-sync` | `feature-analyst` x3, `api-contracts`, `security-reviewer` (device tokens, offline licences) | POS-BE-009/019/021/023, licence contracts | open question on lent permissions and `cash.*` settings; POS-BE-029 filed-not-built |
| 5 | diner-ordering, order-management | 8 | `diner-orders`, `order-status-workflow`, `dashboard-orders` | `feature-analyst` x3, `security-reviewer` (public endpoints) | none | none known |
| 6 | stock-and-purchasing | 5 | `supplier-invoices-payments` | `feature-analyst` x2, `database-reviewer` (ledger, costing) | cloud purchasing design `CB-09` | POS purchasing is hidden in tests (`cloud_purchasing_hidden_test.dart`): confirm the intended scope |
| 7 | menu-management, tables-and-qr | 8 | none | `feature-analyst` x2 | bootstrap catalog and tables | none known |
| 8 | restaurant-and-branches, customers | 5 | none | `feature-analyst` x2 | none | none known |
| 9 | reporting-and-insights, platform-admin | 8 | none | `feature-analyst` x2 | none | none known |
| 10 | pos-back-office-and-ops | 6 | none | `feature-analyst` x2 | ETA e-invoicing, installer | `pos-cloud-back-office` footprint is UNVERIFIED |
Next command: `/project-documentation module auth-and-tenancy` (batch 1 starts there) or `/project-documentation all` to run batches in order with a stop after each.

## Modules
| Module | Features | pending | drafted | validated | stale | blocked | Doc |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `shifts-and-cash` | 2 | 1 | 1 | 0 | 0 | 0 | `docs/modules/shifts-and-cash.md` |
| `auth-and-tenancy` | 4 | 0 | 4 | 0 | 0 | 0 | `docs/modules/auth-and-tenancy.md` |
| `roles-and-staff` | 4 | 0 | 4 | 0 | 0 | 0 | `docs/modules/roles-and-staff.md` |
| `pricing-tax-tenders` | 5 | 4 | 1 | 0 | 0 | 0 | `docs/features/tax-rules/` (module doc not written) |
| all other modules (12) | 51 | 51 | 0 | 0 | 0 | 0 | pending |

## Features
| Slug | Module | Status | Cloud HEAD | POS HEAD | Docs date | Validated date | Open unknowns | Doc path | Blocker |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `pos-shifts` | shifts-and-cash | drafted (core; analysis unvalidated) | 06bc8e3 | d592db8 | 2026-10-20 | 2026-10-20 (round 9, first qualifying pass: 2 class-B + 16 class-N, fixed; criterion not met) | 4 | `docs/features/pos-shifts/` | — |
| `auth-login` | auth-and-tenancy | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never (batch-1 passes 2026-10-20: class-B 6, 2, 1, 1, 1 over rounds 1-5, fixed; criterion not met) | see FEATURE.md Unknowns | `docs/features/auth-login/` | — |
| `auth-password-reset` | auth-and-tenancy | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never | see FEATURE.md Unknowns | `docs/features/auth-password-reset/` | — |
| `auth-signup` | auth-and-tenancy | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never | see FEATURE.md Unknowns | `docs/features/auth-signup/` | — |
| `tenant-isolation` | auth-and-tenancy | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never | see FEATURE.md Unknowns | `docs/features/tenant-isolation/` | — |
| `staff-management` | roles-and-staff | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never (batch-1 passes 2026-10-20: class-B 6, 2, 2, 1, 4 over rounds 1-5, fixed; criterion not met) | see FEATURE.md Unknowns | `docs/features/staff-management/` | — |
| `tenant-roles` | roles-and-staff | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never (batch-1 passes 2026-10-20: class-B 5, 5, 1, 2, 1 over rounds 1-5, fixed; criterion not met) | see FEATURE.md Unknowns | `docs/features/tenant-roles/` | — |
| `platform-users` | roles-and-staff | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never | see FEATURE.md Unknowns | `docs/features/platform-users/` | — |
| `pos-pin` | roles-and-staff | drafted | 06bc8e3 | d592db8 | 2026-10-20 | never | see FEATURE.md Unknowns | `docs/features/pos-pin/` | — |
| `tax-rules` | pricing-tax-tenders | drafted (partial scope) | 06bc8e3 | a6f5fe5 | 2026-10-26 | never | 6 (see FEATURE.md Unknowns) | `docs/features/tax-rules/` | — |
| `pos-refunds` | shifts-and-cash | pending | — | — | — | — | — | — | — |
All other seed features in `docs/FEATURE_INVENTORY.md` are `pending` and carry no HEAD.

## Stale items
None recorded.

## Uncovered source
Not yet computed (see `docs/FEATURE_INVENTORY.md`).

Changed 2026-10-25 for features that have **no folder yet** (queued, not blocking): `menu-items` (`Requests/Dashboard/StoreMenuItemRequest.php`, `UpdateMenuItemRequest.php`: category must be live, not soft-deleted) and `menu-categories`. As-built facts, the FK/delete-action table and open decisions for XORD-012/013 are in `docs/harness/investigations/XORD-014-product-category-relationship.md`. Next documentation run: `/project-documentation feature menu-items` and `feature menu-categories` (the report is the evidence index, but every claim there must be re-cited per the seven-file rules).

## Unknowns needing a human
| # | Question | Features affected | Asked on | Answer |
| --- | --- | --- | --- | --- |
| 1 | Is the `acting_user_id = null` "v1 relaxation" still intended (shifts, movements, orders)? | `pos-shifts`, `pos-orders` | 2026-10-20 | open |
| 2 | Should `open` reject a `branch_id` that is not the terminal's branch? | `pos-shifts` | 2026-10-20 | open |
| 3 | How are `cash.*` POS settings (blind close) set, given that no code writes `cash.blind_close`? And should a cloud-bootstrapped till be able to grant `cash.variance.view` / `shift.view_expected_cash` (today only a local role/grant can)? | `pos-shifts` | 2026-10-20 | open |
| 6 | Should a staff role change or staff create/suspend/delete bump `pos_config_version`, given the KNOWN GAP in `PosConfigVersion.php:30-33` (tills pick changes up only when something else bumps the version)? | `staff-management`, `tenant-roles`, `pos-pin` | 2026-10-20 | open |
| 7 | Should role-delete reassignment (`reassign_to`) check that the target role is not stronger than the actor, as staff create/update do? | `tenant-roles` | 2026-10-20 | open |
| 8 | Do existing tenants' protected Admin roles need a backfill for capabilities added after 2026-08-22 (`pos.*`, `customers.create`, `purchase.manage`)? Production `roles` data was not read. | `tenant-roles` | 2026-10-20 | open |
| 9 | Should `StaffController` refuse reset-password, update and delete of a staff member whose role is stronger than the actor's (today only the `role_id` in the payload is checked)? Found by code reading, no test; no code changed. | `staff-management`, `tenant-roles` | 2026-10-20 | open |
| 10 | Should the login response carry the restaurant display name the POS reads (`data.restaurant.name`; today `RestaurantResource` has only `name_ar`/`name_en`)? Found by code reading, not run. | `auth-login` | 2026-10-20 | open |
| 5 | Should supervisor-lent permissions (the approver) be sent to the cloud, since the cloud checks the acting cashier's own capability and defers the rest forever? | `pos-shifts` | 2026-10-20 | open |
| 4 | How do locally created POS staff ids relate to cloud `users.id` when a shift is synced? | `pos-shifts`, `tenant-roles` | 2026-10-20 | open |

## Run log
| Date | Command | Result | Files changed | Stopped because |
| --- | --- | --- | --- | --- |
| 2026-10-26 | `update tax-rules` after XORD-027 (VAT box moves the default group); feature had no folder, so the seven files were created for the traced slice only | drafted, partial: offline VAT rate, default group, cart label, cloud rule → bundle hand-off; cloud dashboard screen, pricing engine beyond the tax step, ETA, reports untraced (UNVERIFIED); no independent validation pass | `docs/features/tax-rules/*`, `docs/FEATURE_INVENTORY.md`, `docs/DOCUMENTATION_PROGRESS.md` | scope: one slice, by design |
| 2026-10-25 | `/bug-investigation` XORD-014 (product–category relationship), knowledge update limited to a report plus queue entry | relationship exists and is FK-enforced on both sides; 1 cloud defect fixed test-first (item accepted under a soft-deleted category); full cloud suite 1090 passed; POS not run (needs consented PostgreSQL); `menu-items`/`menu-categories` stay `pending` (no folders) | `docs/harness/investigations/XORD-014-product-category-relationship.md`, `docs/DOCUMENTATION_PROGRESS.md`; product: `StoreMenuItemRequest.php`, `UpdateMenuItemRequest.php`, `tests/Feature/CategoryAndItemTest.php` | feature folders need seven files each; decisions 1-4 in the report await the owner before XORD-012/013 |
| 2026-10-20 | `scan` (route level) + `plan` | inventory deepened: 252 routes / 77 controllers indexed, 18 POS client paths matched (17 routes, 2 for filed-not-built POS-BE-029), footprints and route counts set for 63 rows; 10 batches planned | `docs/FEATURE_INVENTORY.md`, `docs/PROJECT_OVERVIEW.md`, `docs/DOCUMENTATION_PROGRESS.md`, `docs/architecture/{cloud-route-index,web-route-index,feature-route-map,README}.md`, `scripts/harness/{route-index,web-route-index}.py` | scan and plan complete; no feature documented beyond `pos-shifts` |
| 2026-10-20 | `module auth-and-tenancy` + `module roles-and-staff` (batch 1): 8 features drafted, plus qualifying passes on the 3 P0 features (fresh `code-reviewer` each) | 17 class-B found and fixed (auth-login 6, staff-management 6, tenant-roles 5), none promoted; 11 absence rows added to the inventory; citations 515 resolve, 0 problems | `docs/features/{auth-login,auth-password-reset,auth-signup,tenant-isolation,staff-management,tenant-roles,platform-users,pos-pin}/*`, `docs/modules/{auth-and-tenancy,roles-and-staff}.md`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-batch1-p0-qualifying-passes-report.md` | batch complete; batch 2 needs the owner's go-ahead |
| 2026-10-20 | `validate` round 5 on `auth-login`, `staff-management`, `tenant-roles` (fresh `code-reviewer` each, producer/consumer check added) | class-B 1 / 4 / 1 confirmed and fixed (class-N 5 / 6 / 9); none promoted; criterion has not converged in five rounds; one reviewer claim and one author correction were wrong and caught by a grep | `docs/features/{auth-login,staff-management,tenant-roles}/*`, `docs/validation/2026-10-20-batch1-round5-qualifying-passes-report.md` | owner decision needed on the criterion or on stopping |
| 2026-10-20 | `validate` round 4 on `auth-login`, `staff-management`, `tenant-roles` (fresh `code-reviewer` each, clause-by-clause brief) | class-B 1 / 1 / 2 confirmed and fixed (class-N 9 / 11 / 10); none promoted; findings: login response has no restaurant `name` key, `acting_user_id` refusal, two over-broad statements | `docs/features/{auth-login,staff-management,tenant-roles}/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-batch1-round4-qualifying-passes-report.md` | owner decides; recommendation: keep drafted and move to batch 2 |
| 2026-10-20 | `validate` round 3 on `auth-login`, `staff-management`, `tenant-roles` (fresh `code-reviewer` each, cross-file consistency check added) | class-B 1 / 2 / 1 confirmed and fixed (class-N 11 / 11 / 13); none promoted; three of the four came from round-2 additions | `docs/features/{auth-login,staff-management,tenant-roles}/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-batch1-round3-qualifying-passes-report.md` | owner decides: move on or round 4 |
| 2026-10-20 | `validate` round 2 on `auth-login`, `staff-management`, `tenant-roles` (fresh `code-reviewer` each) | class-B 2 / 2 / 5 confirmed and fixed (class-N 11 / 18 / 14); none promoted; raised a possible staff-update privilege gap (open question 9) | `docs/features/{auth-login,staff-management,tenant-roles}/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-batch1-round2-qualifying-passes-report.md` | owner decides: round 3 or move on |
| 2026-10-20 | `validate pos-shifts` (round 9, qualifying pass under the owner-approved criterion, fresh reviewer) | 2 class-B (BR-8 POS enforcement layer; error envelope scope) + 16 class-N found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-pos-shifts-round9-qualifying-pass-report.md`, skill rules, `scripts/harness/check-citations.py` | confirmed class-B findings, so `validated` not allowed |
| 2026-10-20 | `validate pos-shifts` (round 8, core only, fresh reviewer, focus on round-7 edits) | core: 3 wrong/stale, 5 missing, 2 belongs-in-analysis, 3 unverifiable, style found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-pos-shifts-round8-core-validation-report.md` | validator found wrong items, so `validated` not allowed |
| 2026-10-20 | `validate pos-shifts` (round 7, core only, fresh reviewer, focus on round-6 edits) | core: 2 wrong/stale, 3 belongs-in-analysis, 5 missing, 1 inconsistency, style found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/FEATURE_INVENTORY.md`, `docs/modules/shifts-and-cash.md`, `docs/validation/2026-10-20-pos-shifts-round7-core-validation-report.md` | validator found wrong items, so `validated` not allowed |
| 2026-10-20 | split + `validate pos-shifts` (round 6, core only, fresh reviewer) | core: 4 wrong/stale (citation-level), 7 belongs-in-analysis, 4 missing, 7 style found, fixed; not promoted | `docs/features/pos-shifts/*` (new `BEHAVIORAL_ANALYSIS.md`), `docs/FEATURE_INVENTORY.md`, `docs/modules/shifts-and-cash.md`, `docs/validation/2026-10-20-pos-shifts-round6-core-validation-report.md`, skill rules and template | validator found wrong items, so `validated` not allowed |
| 2026-10-20 | `validate pos-shifts` (round 5, fresh reviewer, focus on round-4 additions) | 5 wrong, 2 unverifiable, 5 missing found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-pos-shifts-round5-validation-report.md` | validator found wrong items; findings not converging (6, 7, 4, 3, 5) |
| 2026-10-20 | `validate pos-shifts` (round 4, fresh reviewer, focus on round-3 edits) | 3 wrong, 6 missing groups, 5 wording items found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/modules/shifts-and-cash.md`, `docs/validation/2026-10-20-pos-shifts-round4-validation-report.md` | validator found wrong items, so `validated` not allowed |
| 2026-10-20 | `validate pos-shifts` (round 3, fresh reviewer, focus on round-2 edits) | 4 wrong, 2 stale, 3 missing groups found, fixed; not promoted | `docs/features/pos-shifts/*`, `docs/validation/2026-10-20-pos-shifts-round3-validation-report.md`, `.claude/skills/project-documentation/references/validation-rules.md` | validator found wrong items, so `validated` not allowed |
| 2026-10-20 | `validate pos-shifts` (round 2, fresh reviewer) | 7 wrong claims found, fixed; stays `drafted` | `docs/features/pos-shifts/*`, `docs/FEATURE_INVENTORY.md`, `docs/validation/2026-10-20-pos-shifts-revalidation-report.md` | reviewer verdict: not promotable until a further pass |
| 2026-10-20 | seed + pilot (`feature pos-shifts` procedure) + `validate pos-shifts` | inventory seeded; 1 feature drafted; validation found 6 wrong claims, fixed, still `drafted` | `docs/FEATURE_INVENTORY.md`, `docs/PROJECT_OVERVIEW.md`, `docs/DOCUMENTATION_PROGRESS.md`, `docs/modules/shifts-and-cash.md`, `docs/features/pos-shifts/*`, `docs/validation/2026-10-20-pos-shifts-validation-report.md` | scope of the dry run |

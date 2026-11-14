# Batch 1 round-3 report: third qualifying passes (`auth-login`, `staff-management`, `tenant-roles`)

Date: 2026-10-20 · Rounds 1 and 2: `2026-10-20-batch1-p0-qualifying-passes-report.md`, `2026-10-20-batch1-round2-qualifying-passes-report.md` · Repos: cloud `main 06bc8e3`, POS `main d592db8` (unchanged).
Validators: three fresh `code-reviewer` agents (one per feature), same brief as round 2 plus an explicit cross-file consistency check; they were not told earlier findings and did not read `docs/validation/` or the analysis files. Mechanical checks after the fixes: `check-citations.py` 549 line citations, 0 shorthand, 0 problems; `check-docs.py` OK; `verify.sh` structure OK.
Author check: each class-B finding was re-read against the source before acceptance.

## Result: criterion NOT met for any of the three
| Feature | Round 1 B | Round 2 B | Round 3 B (confirmed) | Round 3 N | Status |
| --- | --- | --- | --- | --- | --- |
| `auth-login` | 6 | 2 | 1 | 11 | `drafted` |
| `staff-management` | 6 | 2 | 2 | 11 | `drafted` |
| `tenant-roles` | 5 | 5 | 1 | 13 | `drafted` |
Reviewers rated the load-bearing rules (BR/AC items, routes and middleware, error behavior, contracts, absence claims) correct in all three. Every round-3 class-B finding is in text added or reworded during the earlier fix rounds, not in the original first draft.

## Class-B findings (all fixed)
| Feature | Finding | Evidence |
| --- | --- | --- |
| auth-login | The POS e2e helper does not call the terminal list; it calls branches (`:74`), creates a terminal (`:79`) and requests a pairing code (`:90`) (error in my round-2 addition) | `P:integration_test/support/e2e_platform.dart:63-95` |
| staff-management | "Other tables reference `users` with `nullOnDelete`" too general: `device_tokens.user_id` cascades (error in my round-2 addition) | `C:database/migrations/2026_07_19_000100_create_device_tokens_table.php:17` |
| staff-management | `index` filters `restaurant_id` with no null guard; the doc presented the filter as the tenant boundary without the null case (reviewer confidence medium; the code path is as described, whether such an account exists is UNVERIFIED) | `StaffController.php:49-51`, `Builder.php:988-991` |
| tenant-roles | "Per-action `pos.*` ... not in route middleware" overlooked `pos.provision`, which route middleware enforces (error in my round-2 addition) | `C:routes/api.php:658,781-782` |

## Class-N findings
Fixed: citation ranges (`AuditLogger.php:17-20`, `StoreRestaurantRequest.php:59-61`, `routes/api.php:657,663-664`, `PosConfigVersion.php:30-33`, `RoleController.php:48-50`, `RolesView.vue:104-109`, `postgres_admin_test.dart:417-499`, `cloud_bootstrap_test.dart:145-150`, `permissions_test.dart:73-83`, restaurants FK `:36-39`, `EnsureRole.php:24-25`, test ranges), test-coverage statements (AC-3 create paths only; licence-key test exists; BR-1 half covered; POS key-map tests read only at cited lines), omitted facts (offline paths of the pairing flow, `jti` absence, `users` columns and `password_changed_at` writers, `TenantRoleService::update` overwrite consequence, `down()` bodies, `pos_staff` owner triggers, `acting_user_id` upload basis, PUT without `email` clears it, `StaffForm.vue` shows no message for a `{message}`-only 422), stale headers and changelog wording, contract wording (`API.md` ledger sentence), inventory rows (pagination; `max_users` output corrected).
Not applied: none known.

## Not checked
Runtime behavior; the analysis files; PostgreSQL behavior; production data; execution order of `throttle` and `can:`; `can:` denial body; whether a restaurantless tenant-role account exists.

## Trend and decision
Confirmed class-B findings per feature, rounds 1, 2, 3: auth-login 6, 2, 1; staff-management 6, 2, 2; tenant-roles 5, 5, 1. Three of the four round-3 findings were introduced by my own fixes of the previous round (new sentences added without a source check of each part). The criterion therefore still has not been met, and each fix round that adds new behavioral sentences can create the next round's findings. `validated` remains `drafted` for all three. The criterion's post-pass rule (only single-location facts may be added after a qualifying pass) applies: a fourth pass would be needed only if the owner wants a promotion; otherwise these three are usable as `drafted` with the freshness and spot-check protocol.

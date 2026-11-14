# Batch 1 round-2 report: second qualifying passes (`auth-login`, `staff-management`, `tenant-roles`)

Date: 2026-10-20 · Command: `validate` (second qualifying pass per feature; the first round is `2026-10-20-batch1-p0-qualifying-passes-report.md`) · Repos: cloud `main 06bc8e3`, POS `main d592db8` (unchanged; same uncommitted documentation/agent/script files plus two POS files outside these features).
Validators: three fresh `code-reviewer` agents, one per feature, told nothing about the first round and forbidden from reading `docs/validation/`, the analysis files and other features' docs. Mechanical checks after the fixes: `check-citations.py` 537 line citations, 0 shorthand, 0 problems; `check-docs.py` OK; `verify.sh` structure OK.
Author check: every class-B finding below was re-read against the source (cited lines opened) before it was accepted.

## Result: criterion NOT met for any of the three
| Feature | Class-B (author-confirmed) | Class-N | Status |
| --- | --- | --- | --- |
| `auth-login` | 2 | 11 | `drafted` |
| `staff-management` | 2 | 18 | `drafted` |
| `tenant-roles` | 5 | 14 | `drafted` |
Round 1 (before fixes) had 6, 6 and 5 class-B findings. Two of the round-2 class-B findings are residue of round-1 fixes that were not applied in every location (auth-login B2 `API.md:55`; staff-management B1 `BR-2` wording). The reviewers' coverage statements list every required category.

## Class-B findings (all fixed)
| Feature | # | Finding | Evidence |
| --- | --- | --- | --- |
| auth-login | B1 | Audit "mirror" wording: the activity file is the only sink; `ACTIVITY_LOG_FILE=false` silences login/logout/password-change events; `audit_logs` has no writer. The word came from a stale config comment | `C:app/Services/AuditLogger.php:15-16,47,110-115`, `C:config/platform.php:190-193` |
| auth-login | B2 | `API.md:55` still said "one call" (round-1 B1 patched `FEATURE.md` only) | `P:lib/data/cloud/cloud_provisioning_repository.dart:132,164` |
| staff-management | B1 | `BR-2` still said the owner is "not visible" (round-1 B1 patched Summary and AC-2 only); `index` lists the owner | `StaffController.php:47-59`, `TenantRbacTest.php:508` |
| staff-management | B2 | AC-6 / test table implied no cloud test of the bootstrap `staff[]` payload; two exist | `C:tests/Feature/Pos/PosProvisioningTest.php:266-271`, `PosPurchaseCapabilityWithheldTest.php:20-27` |
| tenant-roles | B1 | BR-4/AC-3 stated as an unconditional invariant; role-delete reassignment has no above-self check | `RoleController.php:99-130`, `TenantUserService.php:108-114` |
| tenant-roles | B2 | `DELETE` body described as `{"data": {...}}`; the wire body is `{"reassign_to": id}` (axios `data` option) | `W:src/pages/dashboard/RolesView.vue:125-127`, `RoleController.php:102`, `TenantRbacTest.php:381` |
| tenant-roles | B3 | `pulse` "zeroes" counts; it returns `null` (my round-1 fix copied a stale route comment) | `PulseController.php:34-40`, `TenantRbacTest.php:164-173` |
| tenant-roles | B4 | "No unit tests for the enums" false: feature tests assert enum behavior | `PosFoundationsTest.php:49-72`, `PurchasingFoundationsTest.php`, `CapabilityVerbsTest.php:194-200` |
| tenant-roles | B5 | AC-6 "no tenant capabilities" vs `Gate::before` passing every gate for Super Admin | `AppServiceProvider.php:120`, `User.php:121-123` |

## Class-N findings (fixed unless listed)
Fixed: wrong contract line for POS-BE-022 (now POS-BE-011 `:1013` and POS-BE-022 `:1796`), citation ranges (`DATABASE.md` migration lines `:41`, `:20`/`:25`; `TenantRbacTest.php:445-456,408-443`; `ActivityLogFileTest.php:97-110`; `postgres_admin_test.dart:417-496`; `management_staff_pane.dart:171-183`; `User::$auditExclude` `:24-26`), test attributions and counts (TenantRbacTest has 33 tests; AC-2/AC-5 partial coverage; BR-7 test asserts only the timestamp increase), middleware message keys versus response codes, `UpdateStaffRequest` guard and `ungrantable` unknown resolved, same-second boundary of the password-change check, unknown slug resolving to platform sign-in, omitted facts (framework 404 for unknown ids, notify requires a restaurant, plan lookup null/unknown, suspended counted, `pos_staff` columns and FKs, `users` FKs with `nullOnDelete`, `role_id` sent but not parsed by the POS, `reports.view` and legacy aliases reaching the till, services enforcing `pos.*` instead of middleware, PIN routes without route-level `can:`, `Restaurant.php:219` stale comment, POS_TO_BACKEND copy of POS-BE-002 out of date), 5 more auth-login absence rows (inventory "Absent").
Not applied: the unresolved middleware-order question for `throttle` versus `can:` on the reset route (recorded UNVERIFIED); the Vue display of a `{message}`-only 422 (UNVERIFIED).

## Product finding raised by the staff-management reviewer (not a documentation defect)
By code reading only (no test, not executed): `guardTarget` does not compare the target's capabilities with the actor's, and `resetPassword` returns a new plaintext password. A staff member holding `staff.view` and `staff.update` could therefore reset the password of a staff account with a stronger role and sign in as it. The same holds for suspend/delete with `staff.delete`. I re-read `StaffController.php:105-124,154-170` and `UpdateStaffRequest.php:40-43`: the path is as described. Recorded in `staff-management/BEHAVIORAL_ANALYSIS.md` H and as open question 9 in `DOCUMENTATION_PROGRESS.md`; no code was changed. The related role-delete reassignment gap is open question 7.

## Not checked
Runtime behavior; the analysis files; production data; PostgreSQL behavior; Arabic strings; execution order of `throttle` and `can:`; framework 404 and `can:` denial bodies; Vue rendering of plan-limit 422.

## Status decision
All three stay `drafted`. Two rounds on three P0 features gave 17 then 9 confirmed class-B findings (6/6/5 then 2/2/5), and a third of the round-2 findings were residue of unfinished round-1 fixes. Evidence that fixes should be applied by search across all files of a feature (`grep` for the old wording) rather than by line. Options for the owner: round 3 on `tenant-roles` (the largest remainder, now fixed), round 3 on all three, or keep `drafted` and move to batch 2.

# Batch 1 round-5 report: fifth qualifying passes (`auth-login`, `staff-management`, `tenant-roles`)

Date: 2026-10-20 · Earlier rounds 1-4 in `docs/validation/2026-10-20-batch1-*-report.md` · Repos: cloud `main 06bc8e3`, POS `main d592db8` (unchanged).
Validators: three fresh `code-reviewer` agents, the round-4 brief plus an explicit producer-and-consumer check for every response key or request field. Mechanical checks after the fixes: `check-citations.py` 567 line citations, 0 shorthand, 0 problems; `check-docs.py` OK; `verify.sh` structure OK.
Author check: each class-B finding was re-read against the source. One reviewer claim was wrong and one correction of mine was wrong (below).

## Result: criterion NOT met for any of the three
| Feature | B rounds 1-5 | Round 5 N | Status |
| --- | --- | --- | --- |
| `auth-login` | 6, 2, 1, 1, 1 | 5 | `drafted` |
| `staff-management` | 6, 2, 2, 1, 4 | 6 | `drafted` |
| `tenant-roles` | 5, 5, 1, 2, 1 | 9 | `drafted` |

## Class-B findings (all confirmed and fixed)
| Feature | Finding | Evidence | Origin |
| --- | --- | --- | --- |
| auth-login | `API.md` error row said a suspended account gets 403 on dashboard routes; on a bearer request the guard returns 401 first (FEATURE.md already said so) | `C:app/Providers/AppServiceProvider.php:233-237` | first draft (not carried to `API.md` in round 1) |
| staff-management | `pos_staff` referencing tables "use RESTRICT or SET NULL": two use `ON DELETE CASCADE` | `P:lib/data/postgres/migrations.dart:2113,2136` | round-4 addition |
| staff-management | BR-3 "403 for own account": an owner gets 404 first | `StaffController.php:161-167` | round-2 addition |
| staff-management | `acting_user_id` listed on payments; POS payments travel inside the order request | `P:lib/data/cloud/outbox_drain.dart:163,249,687,754,810` | round-4 addition |
| staff-management | `acting_user_id` rule incomplete: null accepted; a known user lacking the verb gets 403 | `PosOrderService.php:463-484` | round-4 addition |
| tenant-roles | `pos.void` attributed to `PosOrderService`; it is selected in `PosRefundService` | `PosRefundService.php:87-89` | round-3 addition |
| tenant-roles | omitted that per-action `pos.*` enforcement happens only when `acting_user_id` is sent (every request declares it nullable) | `PosOrderService.php:470-474`, `PosRefundService.php:304-309` | round-3 addition |

## Author errors caught in this round
- A reviewer said `staff.manage` and `settings.manage` appear on the till only in message tables and fakes. I copied that into the doc without a search; a grep then showed the till's own repositories check them (`postgres_admin_repositories.dart:174,274,459`, `postgres_service_charges_repository.dart:84`, `postgres_catalog_admin_repository.dart:539`). Corrected before this report. Lesson: re-run every reviewer-supplied absence or "only" claim before writing it.
- A path I cited (`.../application/admin_messages.dart`) did not exist; the citation checker caught it.

## Class-N findings
Fixed: citation ranges (`RestaurantResource.php:22-23`, `ProfileView.vue:120-140`, POS-BE-030 heading `:2297`), test attributions (PlanEntitlementTest/RestaurantFeatureTest, AC-3 create paths, `postgres_permissions_test.dart:83-100`, `TenantRbacTest.php:564`), pulse null rule (`orders.view`/`bills.view` not `.read`), 401 in the error list, `login` producers table (e2e helper), staff-management temp-password sentence, guardTarget/`subscription.writable` order, counter-evidence for the null-restaurant case, AC-5 extra tests, PIN-bump route to tills, header count.
Not applied: CHANGELOG entries for rounds 3-5 stay generic (they point to the reports).

## Not checked
Runtime behavior; analysis files; PostgreSQL behavior; whether the cloud-till paths that check `staff.manage`/`settings.manage` are reachable; Vue template rendering; the 429 and `can:` denial bodies.

## Trend and decision
Confirmed class-B findings per round (auth-login, staff-management, tenant-roles): round 1: 6/6/5; round 2: 2/2/5; round 3: 1/2/1; round 4: 1/1/2; round 5: 1/4/1. Fifteen reviewer runs on three features. Every round-5 finding sits in text added by an earlier fix round or in a sentence of the first draft that no earlier reviewer happened to test, and the staff-management count rose again because that round's fixes added new enumerations. The criterion has not been met after five rounds. All three remain `drafted`. Recommendation unchanged: stop validating batch 1, rely on the freshness and spot-check protocol, and continue with batch 2. If the owner wants a `validated` status for these three, the criterion itself needs a decision (for example, allowing class-B findings that only concern omissions of qualifiers, or capping the number of rounds), because the current rule has not converged in five rounds.

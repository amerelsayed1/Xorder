# Batch 1 round-4 report: fourth qualifying passes (`auth-login`, `staff-management`, `tenant-roles`)

Date: 2026-10-20 · Earlier rounds: `2026-10-20-batch1-p0-qualifying-passes-report.md` (1), `...-round2-...` (2), `...-round3-...` (3) · Repos: cloud `main 06bc8e3`, POS `main d592db8` (unchanged).
Validators: three fresh `code-reviewer` agents with the round-3 brief plus an instruction to test every clause of each behavioral sentence and every "only/every/also/most/no X" word. They were not told earlier findings and did not read `docs/validation/` or the analysis files. Mechanical checks after the fixes: `check-citations.py` 556 line citations, 0 shorthand, 0 problems; `check-docs.py` OK; `verify.sh` structure OK.
Author check: each class-B finding was re-read against the source before acceptance.

## Result: criterion NOT met for any of the three
| Feature | B rounds 1, 2, 3, 4 | Round 4 N | Status |
| --- | --- | --- | --- |
| `auth-login` | 6, 2, 1, 1 | 9 | `drafted` |
| `staff-management` | 6, 2, 2, 1 | 11 | `drafted` |
| `tenant-roles` | 5, 5, 1, 2 | 10 | `drafted` |

## Class-B findings (all confirmed and fixed)
| Feature | Finding | Evidence | Origin |
| --- | --- | --- | --- |
| auth-login | The POS reads `data.restaurant.name` from the login response, but `RestaurantResource` has `name_ar` and `name_en` and no `name`; so the POS never finds a display name there and falls back to the slug (by reading, not run) | `C:app/Http/Resources/RestaurantResource.php:11-12`, `P:lib/data/cloud/cloud_provisioning_repository.dart:127-130,175` | first draft (a contract fact stated without checking the key on the producer side) |
| staff-management | "A hard-deleted cloud user leaves ids the cloud columns cannot resolve" is wrong: the cloud accepts `acting_user_id` only for an ACTIVE user of the same restaurant and otherwise refuses with 422 | `C:app/Services/PosOrderService.php:470-484`, `PosShiftService.php:325-332` | round-3 addition |
| tenant-roles | "No migration backfills new capabilities into existing roles" unscoped: migrations rewrote stored roles for the verb split and added `live.view` | `C:database/migrations/2026_08_23_000400_grant_live_view_to_roles_that_had_it.php:19-36` | first draft |
| tenant-roles | "`pos.*` verbs ... enforced inside services" overbroad: `pos.reprint` is enforced nowhere | grep of `app` and `routes` (only `TenantCapability.php:101`) | round-3 addition |

## Product observations raised (documentation only, no code changed)
- Login response lacks a restaurant `name` key although the POS reads one (`auth-login/API.md`). Candidate open question 10 below.
- A deleted or suspended staff row still on a till gets that person's uploads refused with 422 (`staff-management/BEHAVIORAL_ANALYSIS.md` I; how the till treats the 422 was not traced).

## Class-N findings
Fixed: citation ranges and off-by-one cites, test attributions and gap lists (AC-3 PUT paths, BR-3 evidence, RestaurantFeatureTest has no HTTP calls, PostgreSQL permissions test is a migration test), omitted stale comments and the Arabic language block, `pos_staff` FK actions, seeder upsert on `id` only, extra Vue consumers, middleware-priority reading for the reset route (throttle runs before `can:`, from reading the framework kernel list), `password_changed_at` writers, reply wording of translation keys, POS_TO_BACKEND index row READY versus body APPROVED, a recorded absence command note.
Not applied: the contract link for the bootstrap `staff[]` block (`BACKEND_TO_POS.md:1976-1983`, POS-BE-024 for the PIN) is noted only here; its text says `pin_hash` while the code sends a `pin` block (docs follow the code).

## Not checked
Runtime behavior; the analysis files; PostgreSQL behavior; how the till handles a 422 on upload; Vue template rendering.

## Trend and decision
Confirmed class-B per round, per feature (auth-login, staff-management, tenant-roles): round 1: 6/6/5; round 2: 2/2/5; round 3: 1/2/1; round 4: 1/1/2. The number is not reaching zero: two of the four round-4 findings were new sentences from round 3, two were first-draft statements no earlier pass had tested. Each pass of three fresh reviewers still finds about one behavioral error per feature. All three stay `drafted`; four passes (12 reviewer runs) do not support promotion under the owner-approved criterion, and a fifth would be the same cost with the same expected outcome. Recommendation: keep batch 1 as `drafted`, rely on the freshness and spot-check protocol, and continue with batch 2 under the plan policy.

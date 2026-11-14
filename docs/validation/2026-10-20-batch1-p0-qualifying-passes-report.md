# Batch 1 validation report: P0 qualifying passes (`auth-login`, `staff-management`, `tenant-roles`)

Date: 2026-10-20 · Command: `module auth-and-tenancy`, then `roles-and-staff` (batch 1), policy "drafted plus mechanical checks; independent validation only for P0 features" · Repos: cloud `main 06bc8e3`, POS `main d592db8` (both unchanged since the documented revisions; same uncommitted documentation/agent/script files).
Validators: one fresh `code-reviewer` agent per P0 feature, each given the feature's core docs and the source, not the author's notes. Mechanical checks before the passes: `check-citations.py` 489 line citations, 0 shorthand, 0 problems; `check-docs.py` OK. After the fixes: `check-citations.py` 515 line citations, 0 shorthand, 0 problems; `check-docs.py` OK; `verify.sh` harness structure OK.
Author checks: every class-B finding below was re-read against the source before the fix (the fix text cites the lines).

## Result: criterion NOT met for any of the three
| Feature | Class-B (confirmed) | Class-N | Status after pass |
| --- | --- | --- | --- |
| `auth-login` | 6 | 16 | `drafted` |
| `staff-management` | 6 | 10 groups | `drafted` |
| `tenant-roles` | 5 | 15 | `drafted` |
`validated` needs zero confirmed class-B findings in a qualifying pass (`references/validation-rules.md`). None qualified; a new pass would be needed after these fixes. The five non-P0 features (`auth-password-reset`, `auth-signup`, `tenant-isolation`, `platform-users`, `pos-pin`) were not independently validated by plan policy and stay `drafted`.

## Class-B findings (fixed)
### `auth-login`
| # | Finding | Evidence | Fix |
| --- | --- | --- | --- |
| B1 | "token used for one call" was wrong: the POS uses the login JWT for `listBranches` and `listTerminals` (connect), `issuePairingCode` (adopt) and `registerTerminal` (manual); the code comment and contract text say one call; any staff holding `pos.provision` may use Path B | `P:lib/data/cloud/cloud_provisioning_repository.dart:82-132,164,226-242,297-315`; `BACKEND_TO_POS.md:1866-1870,1944` | per-flow description, divergence recorded |
| B2 | Username uniqueness described as database-only; request rules also validate it | `StoreStaffRequest.php:30`, `UpdateStaffRequest.php:29`, `StorePlatformUserRequest.php:26`, `UpdatePlatformUserRequest.php:26`, `UpdateRestaurantAdminRequest.php:31` | reworded |
| B3 | "Expression index serves the login lookup" unsupported | lookup shape `AuthController.php:32-41`, Eloquent provider | marked UNVERIFIED |
| B4 | Roles migration "re-creates" the index: it does so on SQLite only | `2026_08_22_000100_create_roles_table.php:119-128` | corrected (also in staff/roles docs) |
| B5 | "No coordination item names the login/auth endpoints" too broad | `BACKEND_TO_POS.md:2305` (POS-BE-030 names `/api/auth/me`) | narrowed to `/api/auth/login`, related items listed, cloud copy named |
| B6 | `sessions` table "unused" | `config/session.php:21` defaults the driver to `database` | "not used by the JWT guard; web-route use UNVERIFIED" |
### `staff-management`
| # | Finding | Fix |
| --- | --- | --- |
| B1 | Summary/AC-2 said the owner is invisible; `index` lists the owner (marked `is_owner`) and only the target endpoints 404 | Summary, AC-2 reworded |
| B2 | Order of FormRequest, plan limit and `guardTarget` misdescribed (FormRequest validation runs before the action body; for `update`, before `guardTarget`) | behaviors 2-3 reworded with line cites |
| B3 | BR-8 "writes require an active subscription" imprecise: no-restaurant, ARCHIVED, SUSPENDED restaurant, and subscription state only when `ENFORCE_SUBSCRIPTION_WRITES` (default true, `config/platform.php:171`); reads are outside | BR-8 rewritten |
| B4 | "Suspended owner cannot create staff (403)" ignores that a bearer request fails at the guard (401); 403 only with `actingAs` | edge case and AC-5 rewritten |
| B5 | Error codes listed as `staff_not_found` etc.; bodies carry only the localized `message` | API error formats rewritten |
| B6 | `resetPassword` and `destroy` have no FormRequest; `UpdateStaffRequest` cited without path | validation section corrected |
### `tenant-roles`
| # | Finding | Fix |
| --- | --- | --- |
| B1 | Role writes do not bump `pos_config_version` (KNOWN GAP); bootstrap ETag 304 and the seeder skip equal versions, so "capabilities change when it next downloads the bootstrap" was unsupported | facts moved into the POS paragraph; consequence entries I and J in `BEHAVIORAL_ANALYSIS.md` |
| B2 | "Server-side gates on every route" false: shell endpoints are open to all tenant accounts (`routes/api.php:274-297`) | Security section and Actors corrected |
| B3 | "No audit event found" misleading: `Role` uses `Auditable` | `Role.php:21`, `Auditable.php:22-27` cited; `reassignRole` audit question moved to analysis I |
| B4 | "Adding a capability needs ..." unsupported | moved to analysis K (lead, low confidence) |
| B5 | Contract ledger: POS-BE-002 (READY) request names `GET /api/dashboard/roles/capabilities` (`POS_TO_BACKEND.md:183`) | cross-application section, API and inventory corrected |

## Class-N findings
Fixed in the docs: config line cites (`config/jwt.php:16,29,37`), audit switch `ACTIVITY_LOG_FILE` and test attributions (`AuditLogTest.php:74,84-88`, `ActivityLogFileTest.php:63-69,103`), AC-1 test attribution, change-password 422 coverage (`ChangePasswordTest.php:48,60,72`), `role:` call sites (`routes/api.php:782`; `uploads/image` `:827` is `auth:jwt` only), suspended-user 401 versus 403 ordering, FK `ON DELETE SET NULL`, "written for PostgreSQL" wording, POS verdict handling per flow, platform-user lookup with null `restaurant_id` (resolved: `Builder.php:988-991`), limitation inferences moved to analysis, absence claims given recorded commands (inventory "Absent", 11 new rows), page-level citation corrections (`UserResource.php:36`, pulse comment `:279-282`), `User` `Auditable` unknown resolved.
Not applied: none known; reviewers' minor style notes were taken where they concerned accuracy only.

## Not checked
Runtime behavior; `BEHAVIORAL_ANALYSIS.md` (unvalidated by design); Arabic strings; production data (`roles`, `users`); PostgreSQL behavior of the username expression index; heartbeat-driven bootstrap refresh; whether query-builder `update` in `reassignRole` fires audit events; the five features without an independent pass.

## Status decision
All eight batch-1 features remain `drafted`. The three P0 passes confirm the pattern seen on `pos-shifts`: first-draft documentation contains 5 to 6 behavioral overstatements per feature (enforcement layer, "every", "only", ordering), which fresh reviewers find reliably. Options for the owner: a second qualifying pass on each P0 feature after these fixes, or keep `drafted` and rely on the freshness/spot-check protocol while moving to batch 2.

# Behavioral analysis: Restaurant staff accounts

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Bootstrap freshness after staff changes
- Claim: only the PIN controller bumps `pos_config_version`; staff create/update/suspend/delete do not, so tills may not see them until something else changes the bootstrap version/ETag
- Trace: `C:app/Services/PosConfigVersion.php:30-33,55-58` (hook list excludes `User`; KNOWN GAP comment), `PosPinController.php:44,65`; ETag is `"pos-<restaurant>-v<pos_config_version>"` (`C:app/Http/Controllers/Pos/BootstrapController.php:25-33`); the till skips an equal or older version (`P:lib/data/cloud/bootstrap_seeder.dart:71-76`); heartbeat refresh not traced
- Confidence: medium. Would be confirmed by: a test that creates staff then requests the bootstrap with the old ETag

## B. Deleted or suspended staff on tills
- Claim: the bootstrap sends only ACTIVE users and the POS deactivates rows missing from a non-empty list, so a deleted user may keep working on a till until the next bundle; an empty list deactivates nobody
- Trace: `C:app/Services/PosBootstrapService.php:305-336`, `P:lib/data/cloud/bootstrap_seeder.dart:493-505`
- Confidence: medium. Would be confirmed by: a POS seeder test

## C. Plan-limit race
- Claim: two simultaneous creates can both pass the check
- Trace: `C:app/Http/Controllers/Dashboard/StaffController.php:75-81` (no lock or transaction)
- Confidence: medium. Would be confirmed by: a concurrent test

## D. Mail failure
- Claim: credentials mail runs synchronously after the commit; a mail exception could return 500 after the account exists
- Trace: `C:app/Services/TenantUserService.php:116-123`
- Confidence: low-medium. Would be confirmed by: a test with a failing mailer

## E. Username uniqueness race
- Claim: the request rule is check-then-insert; the unique expression index is the backstop and a race would surface as a database error
- Trace: `StoreStaffRequest.php`, migration `2026_07_21_000300_make_username_unique_per_tenant.php:20`
- Confidence: medium. Would be confirmed by: a concurrent test on PostgreSQL

## F. Legacy aliases reach tills
- Claim: a cloud staff member holding the four `staff.*` verbs arrives at the till with `staff.manage`, which is a real POS key read by POS code
- Trace: `C:app/Models/User.php:167-183`, `PosBootstrapService.php:322-331`, `P:lib/domain/models/permissions.dart:27,238`, `P:lib/data/postgres/postgres_admin_repositories.dart:1104`
- Confidence: medium. Would be confirmed by: a POS test feeding such a bundle

## G. `setGrants` on a cloud till
- Claim: the POS repository appears not to refuse per-person grants on a cloud till and the bundle does not carry them; whether a later bundle overwrites them was not traced
- Trace: `P:lib/data/postgres/postgres_admin_repositories.dart:846-871`, `bootstrap_seeder.dart:465-487`
- Confidence: medium. Would be confirmed by: a POS test

## H. Staff-update holder versus a stronger staff member
- Claim: `guardTarget` does not compare the target's capabilities with the actor's, so a staff member holding `staff.view` and `staff.update` could `POST /staff/{id}/reset-password` for a staff account whose role is stronger, receive the new plaintext password in the response and sign in as that account; `staff.delete` likewise allows deleting it, and `update` of such an account is refused only when the payload's `role_id` is above the actor (BR-4), so a no-op role would pass
- Trace: `C:app/Http/Controllers/Dashboard/StaffController.php:105-124,154-170`, `C:app/Http/Requests/Dashboard/UpdateStaffRequest.php:40-43`, `C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php:64-81`
- Confidence: medium-high for the path; not executed, no test. Would be confirmed by: a feature test with a limited actor and a target holding a role above them. Recorded as open question 9 in `DOCUMENTATION_PROGRESS.md`

## I. Deleted or suspended staff still on a till
- Claim: the cloud refuses an `acting_user_id` that is not an ACTIVE user of the same restaurant with 422 `VALIDATION_FAILED`, so a till that still holds a deleted or suspended staff row gets that person's uploads (orders, payments, shifts, cash movements, refunds) refused until the next bundle deactivates the row; how the till handles the 422 (retry, quarantine) was not traced here
- Trace: `C:app/Services/PosOrderService.php:470-484`, `PosShiftService.php:325-332`, `P:lib/data/cloud/outbox_drain.dart:163,249,687,754,810,920`, `P:lib/data/cloud/bootstrap_seeder.dart:493-505`
- Confidence: medium. Would be confirmed by: a cloud test with a suspended acting user plus the POS drain handling of 422


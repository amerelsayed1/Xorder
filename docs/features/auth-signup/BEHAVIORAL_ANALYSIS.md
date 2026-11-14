# Behavioral analysis: Self-service restaurant signup

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. A signup tenant probably cannot use PINs or tills
- Claim: signup passes no plan, so the default feature set applies, which lacks `pos`; `feature:pos` routes would answer feature-disabled
- Trace: `C:app/Http/Controllers/Public/SignupController.php:48-60`, `C:app/Services/PlanEntitlementService.php:49-58`, `C:app/Enums/Feature.php:86-95`, `C:routes/api.php:657`; `EnsureFeatureEnabled` behavior read in `tenant-roles` evidence
- Confidence: medium. Would be confirmed by: a test: signup then PUT staff pin → 403

## B. Mail failure after commit
- Claim: restaurant and owner exist even if the credentials mail throws; the request may return 500
- Trace: `C:app/Services/RestaurantProvisioningService.php:150-153`
- Confidence: low-medium. Would be confirmed by: a test with a failing mailer

## C. Honeypot is not uniform with validation
- Claim: a bot filling `website` still hits email validation first, so a duplicate email gives 422 not the fake success
- Trace: `SignupController.php:32-36`
- Confidence: high, low impact. Would be confirmed by: a test

## D. Email uniqueness race
- Claim: the `unique:users,email` rule is check-then-insert; whether a database unique index still exists after the column became nullable was not confirmed
- Trace: `C:app/Http/Requests/Public/SignupRequest.php`; migrations `0001_01_01_000000_create_users_table.php:17`, `2026_07_21_000200_add_username_to_users_table.php:40-41`
- Confidence: unknown. Would be confirmed by: a read of the PostgreSQL schema (not permitted here)

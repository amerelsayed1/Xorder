# Behavioral analysis: Tenant isolation (restaurant scope)

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Override is process-global state
- Claim: `TenantContext::overrideId` is static; a path that sets it and fails to clear it would leak the tenant to later work in the same process; the device middleware clears in `finally`, the other setters were not checked for clearing
- Trace: `C:app/Support/TenantContext.php:22-32`, `C:app/Http/Middleware/PosDeviceAuth.php:79-83`, other setters listed in `FEATURE.md`
- Confidence: low-medium. Would be confirmed by: read each setter for a `finally`/clear, or a test

## B. Platform roles other than Super Admin are unscoped by data
- Claim: the scope is off for them only because their `restaurant_id` is null
- Trace: `C:tests/Feature/UserCreationMatrixTest.php:93`, `TenantContext.php:46-51`
- Confidence: high. Would be confirmed by: n/a (design observation)

## C. Controller guard instead of binding scope for staff
- Claim: the `{staff}` binding resolves any user id; isolation rests on `guardTarget`/`PosPinController::guard`; `StaffController::scoped()` is dead code
- Trace: `C:app/Http/Controllers/Dashboard/StaffController.php:142-170`
- Confidence: high within the file; not checked repo-wide. Would be confirmed by: a repo-wide search for unguarded `User` bindings

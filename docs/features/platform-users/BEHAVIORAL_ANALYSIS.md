# Behavioral analysis: Platform (Super Admin portal) users

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Role and status changes apply at the next request
- Claim: the guard re-reads the user per request; `update` does not touch `password_changed_at`, so an existing token stays valid with the new role
- Trace: `C:app/Providers/AppServiceProvider.php:232-239`, `C:app/Services/PlatformUserService.php:63-76`
- Confidence: medium. Would be confirmed by: a test changing a role and calling an endpoint

## B. Suspension of a platform user takes effect at once
- Claim: guard rejects non-ACTIVE users
- Trace: `AppServiceProvider.php:237`
- Confidence: high. Would be confirmed by: a bearer-token test

# Behavioral analysis: Password reset by email

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. The emailed link has no page in this repository
- Claim: the flow cannot be completed from the web apps as built
- Trace: the URL is built at `C:app/Providers/AppServiceProvider.php:90-108`; no route, page or API call for forgot/reset exists in `W:src`, `A:landing/src`, `A:menu/src`, `K:`; the tenant router has a catch-all redirect (`W:src/router/index.js:227`); what the live host serves at `/reset-password` was not checked
- Confidence: medium-high that no Vue UI exists; unknown for the live host. Would be confirmed by: a request to the deployed `/reset-password` path (not permitted here)

## B. Staff without an email cannot use this flow
- Claim: recovery for them is through owner/admin reset endpoints
- Trace: the broker matches `users.email` (nullable); `C:tests/Feature/TenantRbacTest.php:449-458` shows email-less staff exist; admin-side resets: `C:routes/api.php:131,145,321`
- Confidence: medium-high. Would be confirmed by: a test of forgot-password for an account without email

## C. Throttle semantics
- Claim: `throttle:5,1` uses the framework default key and the broker adds a 60-second per-user throttle whose status the controller ignores, so a throttled request still returns the generic 200
- Trace: `C:routes/api.php:88-89`, `C:config/auth.php:109`, `C:app/Http/Controllers/Auth/PasswordResetController.php:19`
- Confidence: medium. Would be confirmed by: tests of repeated requests

## D. Mail transport failure
- Claim: `Password::sendResetLink` is called synchronously with no handling; a transport exception would likely return 500 for existing accounts only, an enumeration oracle
- Trace: `PasswordResetController.php:19`; stock notification not read
- Confidence: low. Would be confirmed by: a test with a failing mailer

## E. Token reuse after a successful reset
- Claim: the broker is expected to delete used tokens; vendor code not read
- Trace: `PasswordResetController.php:37-48`
- Confidence: low. Would be confirmed by: a test replaying a token

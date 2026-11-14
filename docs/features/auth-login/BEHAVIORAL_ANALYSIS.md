# Behavioral analysis: Login, session token and password change

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Unknown `restaurant` slug falls back to platform users
- Claim: a request with a bogus slug looks up platform users instead of failing
- Trace: `C:app/Http/Controllers/Auth/AuthController.php:99-101` returns null for an unknown slug, so `restaurant_id` is null in the credentials (`:34`), which selects platform users; the SPA then redirects by role (`W:src/pages/LoginView.vue:48-53`)
- Confidence: medium. Would be confirmed by: a test posting an unknown slug with platform credentials

## B. 403 for a suspended account only after a correct password
- Claim: wrong password on a suspended account is 401, the 403 is reachable only with the right password
- Trace: `AuthController.php:45` precedes `:56`
- Confidence: high. Would be confirmed by: a test with a suspended user and a wrong password

## C. Same-second token boundary
- Claim: a token issued in the same second as `password_changed_at` is accepted; the change-password flow relies on this to keep the new token valid
- Trace: `C:app/Support/Jwt.php:24-29` (`iat = time()`) vs `C:app/Providers/AppServiceProvider.php:248-250` (strict `<`), `AuthController.php:149-161`
- Confidence: high for the logic, untested for the boundary. Would be confirmed by: a test with a frozen clock

## D. Suspended restaurants can still sign in and read
- Claim: login and the guard do not read the restaurant; only writes behind `subscription.writable` are refused
- Trace: `AppServiceProvider.php:232-243` (no restaurant lookup), `C:app/Http/Middleware/EnsureSubscriptionAllowsWrites.php:26-31`, SPA `isReadOnly` (`K:api-client/src/auth.js:66-71`)
- Confidence: high for login, medium for individual read routes. Would be confirmed by: route-by-route tests with a suspended restaurant

## E. `rid` strictness on PostgreSQL
- Claim: the strict `!==` between the decoded claim and `restaurant_id` needs both to be integers
- Trace: `AppServiceProvider.php:241`; tests run on SQLite
- Confidence: low. Would be confirmed by: a PostgreSQL run of the token tests

## F. Logout leaves the token valid
- Claim: after logout the same token still authenticates until it expires or the password changes
- Trace: `AuthController.php:116-129` (no revocation) with `Jwt.php:46-53` and the guard
- Confidence: high. Would be confirmed by: a test calling `me` after `logout`

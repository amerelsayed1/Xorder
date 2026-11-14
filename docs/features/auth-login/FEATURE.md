# Feature specification: Login, session token and password change

Status: implemented (cloud API and dashboard SPA; POS uses login for provisioning only)
Slug: `auth-login` · Module: `auth-and-tenancy` · Footprint: shared (POS client call verified: `POST /api/auth/login`)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
Users sign in with a username and password and receive a stateless bearer token (JWT) that authenticates every `auth:jwt` route. The same endpoint serves the Super Admin portal (platform users) and each restaurant's dashboard (tenant users); which one is addressed is decided by the restaurant slug sent in the request or by the Host's first label. Signed-in users can read their profile (`me`), change their password and sign out. Passwords are recovered through `auth-password-reset`.

## Scope and exclusions
Implemented: `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/auth/me`, `POST /api/auth/change-password` (`docs/architecture/cloud-route-index.md`, `C:routes/api.php:87,91-96`); the JWT issue/parse code and the `jwt` guard; role and status gate `EnsureRole`; the Vue login page, API client and router guard; the POS call used when pairing a till.
Not found in code (commands and results in `FEATURE_INVENTORY.md` "Absent", rows for `auth-login`): refresh tokens, a token blocklist or `jti`, a `last_login_at` column, Sanctum token use (the `HasApiTokens` trait is on `User` but `createToken`/`auth:sanctum` are unused), a Vue change-password page for the platform portal, any login or `me` call from the POS other than `login`.

## Actors and permissions
| Actor | Rule | Enforced by | Evidence |
| --- | --- | --- | --- |
| Anyone | may call login | route has only `throttle:login` | `C:routes/api.php:87` |
| Signed-in user | may call logout, me, change-password | `auth:jwt` | `C:routes/api.php:91-96` |
| Platform vs tenant user | dashboard routes require a tenant role, admin routes a platform role | `EnsureRole` (`role:` middleware) | `C:app/Http/Middleware/EnsureRole.php:16-33`, `C:routes/api.php:109,272,782` (`pos/terminals/register` also stacks `role:<tenant roles>`; `uploads/image` at `:826-827` has `auth:jwt` and `throttle:60,1` and no `role:`) |
| Suspended user | refused at login (403); for a bearer request the guard returns no user first (401), so the 403 of `EnsureRole` is reached only when a user is injected without the guard (as `actingAs` does in `C:tests/Feature/TenantRbacTest.php:176`) | `AuthController`, `EnsureRole`, guard | `C:app/Http/Controllers/Auth/AuthController.php:56-64`, `EnsureRole.php:24-26`, `C:app/Providers/AppServiceProvider.php:237` |
Roles: platform `SUPER_ADMIN`, `ADMIN`, `MODERATOR`, `SALES`, `SUPPORT`; tenant `RESTAURANT_ADMIN`, `RESTAURANT_STAFF` (`C:app/Enums/RoleEnum.php:10-21`). Capabilities are documented in `tenant-roles`.

## Current implemented behavior
1. Login resolves the tenant: a non-empty `restaurant` input is looked up as a slug (unknown slug → no tenant); otherwise the Host's first label is looked up; a bare host gives no tenant (`C:app/Http/Controllers/Auth/AuthController.php:97-114`). Credentials `{username, restaurant_id, password}` go to the `users` provider (`:31-41`); no tenant selects platform users (`restaurant_id` null; the framework turns a null credential into `whereNull`: `vendor/laravel/framework/src/Illuminate/Database/Query/Builder.php:988-991`, called from `EloquentUserProvider::retrieveByCredentials` `vendor/laravel/framework/src/Illuminate/Auth/EloquentUserProvider.php:126-136`).
2. Wrong user or password → 401 `auth.failed`, audit `auth.login_failed` (`AuthController.php:45-53`). A correct password on a non-ACTIVE account → 403 `account_suspended`, audit `auth.login_blocked` (`:56-64`). The password is checked first.
3. Success → 200 with `data` (user resource), `token`, `token_type` "Bearer", `expires_in` seconds, `message`; audit `auth.login` (`:66-81`). The user resource keys are id, name, username, email, role, restaurant_id, status, is_owner, role_id, role_name, role_name_ar, capabilities, restaurant (`C:app/Http/Resources/UserResource.php:15-38`).
4. Token: HS256 by default (`JWT_ALGO`), claims `iss`, `sub`, `iat`, `nbf`, `exp`, `rid` (the user's `restaurant_id`); lifetime `JWT_TTL` minutes, default 10080 (7 days); the secret comes from `JWT_SECRET` and an empty secret throws (`C:app/Support/Jwt.php:22-38,55-63`, `C:config/jwt.php:16,29,37` (secret, ttl, algorithm)). No role or status claim, no `jti`.
5. The `jwt` guard returns no user (→ 401) when: no bearer token; the token fails to parse (expired, bad signature, not yet valid, malformed) or has no `sub`; the user does not exist or is not ACTIVE; `rid` is not strictly equal to the user's `restaurant_id`; the user has `password_changed_at` and the token's `iat` is earlier (`C:app/Providers/AppServiceProvider.php:219-254`, `Jwt.php:46-53`). The guard does not read the restaurant.
6. Logout writes audit `auth.logout` and returns a message; the code states that nothing is revoked server-side (`AuthController.php:116-129`).
7. `GET /me` returns the user resource with restaurant features and tenant role loaded (`AuthController.php:132-137`).
8. Change password: validates, sets the new password (hashed by cast) and `password_changed_at = now()`, audits `auth.password_changed`, and returns a **new** token (keys `token`, `token_type`, `expires_in`, `message`; no `data`) (`AuthController.php:145-169`).
9. Rate limits: login 10 per minute per IP and 5 per minute per username+IP (`C:app/Providers/AppServiceProvider.php:175-182`); change-password `throttle:6,1` (`C:routes/api.php:96`).
10. All API requests are forced to JSON, security headers are appended, and the locale comes from the `X-Locale` header or `lang` query parameter (`ar` or `en`) (`C:bootstrap/app.php:49,52,55,67-69`, `C:app/Http/Middleware/SetLocale.php:14-18`).

## User journeys and workflows
- Sign in on a restaurant dashboard host or the admin host; the SPA sends the slug it derives from the host and then routes by role (`W:src/pages/LoginView.vue:41-53`, `W:src/lib/host.js:7-14`).
- Change password: the dashboard profile page posts to change-password and swaps in the new token (`W:src/pages/dashboard/ProfileView.vue:120-140`, `K:api-client/src/auth.js:109`).
- Pair a till: the POS posts `{restaurant, username, password}` with the credentials of staff holding `pos.provision` and does not store the token. Per flow it uses the token for: `connect` → `GET /api/dashboard/branches` and `GET /api/dashboard/pos/terminals`; `adoptTerminal` → `POST /api/dashboard/pos/terminals/{id}/pairing-code`; `registerManually` → `POST /api/pos/terminals/register` (`P:lib/data/cloud/cloud_provisioning_repository.dart:82-132,164,226-242,297-315`, `P:lib/data/cloud/cloud_api.dart:109,129,146,160`). The code comment at `cloud_api.dart:92-93` and the contract text (`apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:1944`, "used for this one call") describe a single call; the built flows use it for one to two calls. `pos.provision` staff (not only the owner) may use it (`BACKEND_TO_POS.md:1866-1870`). `connect` also calls the branch list, which is behind `can:branches.list` (`branches.view` or `tables.view`; `C:routes/api.php:351`, `C:app/Providers/AppServiceProvider.php:148-149`); the terminal routes sit behind `feature:pos` (`C:routes/api.php:657`) and `can:pos.provision` (`:658`); `pos/terminals/{terminal}/pairing-code` is also behind `subscription.writable` and `throttle:10,1` (`:663-664`), so the adopt flow is refused for a restaurant that is not writable.

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | A username is unique per tenant (platform users share one namespace); the same username may exist in two restaurants. | unique expression index on `COALESCE(restaurant_id, 0), username` | `C:database/migrations/2026_07_21_000300_make_username_unique_per_tenant.php:16-20` |
| BR-2 | Usernames are matched in lower case and trimmed. | request and model | `C:app/Http/Requests/Auth/LoginRequest.php:29-34`, `C:app/Models/User.php:42-47` |
| BR-3 | A tenant account only signs in on the tenant the request addresses (another tenant's host or slug is refused); an unknown slug or subdomain resolves to no tenant, and then only platform accounts (`restaurant_id` null) can sign in. | tenant resolution | `AuthController.php:31-41,97-114`; tests `PerTenantAuthTest.php:30,48,58` |
| BR-4 | Wrong credentials → 401; suspended account with the right password → 403. | controller | `AuthController.php:45-64` |
| BR-5 | Every token is bound to the user's `restaurant_id` and issue time; the guard rejects a token whose `rid` differs. | `Jwt::issue`, guard | `C:app/Support/Jwt.php:26-35`; `C:app/Providers/AppServiceProvider.php:241-243` |
| BR-6 | A token whose `iat` (whole seconds) is earlier than the second of the user's last password change is rejected; a token issued within the same second survives. | guard | `C:app/Providers/AppServiceProvider.php:245-251` |
| BR-7 | New passwords (change and reset) must be at least 12 characters with mixed case and a number, confirmed; on change it must differ from the current one, which must be supplied and correct. | request rules | `C:app/Http/Requests/Auth/ChangePasswordRequest.php:25-38`; reset: `C:app/Http/Controllers/Auth/PasswordResetController.php:34` |
| BR-8 | Logout does not revoke the token. | controller (comment) | `AuthController.php:124-128` |
| BR-9 | The login endpoint does not check the restaurant's status or subscription. | absence | `grep RestaurantStatus app/Http/Controllers/Auth` → no match (recorded in `FEATURE_INVENTORY.md` "Absent") |

## Validation and error handling
| Situation | Check | Result | Evidence |
| --- | --- | --- | --- |
| Login body | `username` required string max 150; `password` required string; `remember` sometimes boolean; `restaurant` sometimes nullable string max 255 | 422 (Laravel default shape; not asserted by any test) | `C:app/Http/Requests/Auth/LoginRequest.php:16-25` |
| `remember` | accepted, never read | no effect | `grep -rn "'remember'" app` finds only `C:app/Http/Requests/Auth/LoginRequest.php:19` |
| Wrong credentials | provider lookup and hash check | 401 `{message}` | `AuthController.php:45-53` |
| Suspended | status check | 403 `{message}` | `:56-64` |
| Change password | `current_password` required and checked with `Hash::check`; `password` required, confirmed, different from current, min 12 mixed case numbers | 422 | `ChangePasswordRequest.php:25-38` |
| No/invalid token on `auth:jwt` | guard | 401 | `AppServiceProvider.php:219-254` |
| Wrong role | `EnsureRole` | 403 `no_access` | `EnsureRole.php:28-30` |
| Throttled | limiter | 429 (framework response) | `C:tests/Feature/SecurityHardeningTest.php:154-171` |

## Edge cases and failure handling
- Staff with no email can sign in with a username (`C:tests/Feature/TenantRbacTest.php:445-456`).
- Case-insensitive username (`C:tests/Feature/AuthTest.php:24`).
- A restaurant admin cannot sign in on the super-admin host; a super admin can sign in on the admin host and on a bare host (`C:tests/Feature/PerTenantAuthTest.php:58,67,126`).
- An explicit `restaurant` slug takes precedence over the Host (`PerTenantAuthTest.php:108`).
- Further traced conclusions (unknown slug fallback, same-second timestamps, suspended restaurants): `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
- POS: only `POST /api/auth/login` is called, during pairing (`P:lib/data/cloud/cloud_provisioning_repository.dart:82,226,297`). In `connect` a 401/403/422 is read as a credential verdict and any other non-OK status as WRONG_PLATFORM (`:101-112`); in `adoptTerminal` and `registerManually` an offline reply returns the offline result first (`:231,302`) and every other non-OK result or empty token becomes CREDENTIALS_REJECTED (`:233,304`); in `connect` an offline reply gives PLATFORM_UNREACHABLE (`:87-94`). The POS never calls me, logout, change-password, forgot or reset (commands in `FEATURE_INVENTORY.md` "Absent"). The integration helper `P:integration_test/support/e2e_platform.dart:63-95` also posts to login and uses the token for `GET /api/dashboard/branches` (`:74`), `POST /api/dashboard/pos/terminals` (`:79`, creates a terminal) and the pairing-code call (`:90`). `P:test/core/network_log_test.dart:63` is a log-masking fixture using the URL `https://xorder.io/api/pos/auth/login` (no such cloud route).
- Vue: login/me/logout/change-password through `K:api-client/src/auth.js:75-109`; the token is kept in `localStorage` key `xorder_token`, sent as a Bearer header with `X-Locale`, and cleared on any 401 (`K:api-client/src/api.js:13-27,41-55`).
- Contract ledger: no item names `/api/auth/login` (grep of `auth/login` in both repos' `docs/coordination/*.md`, cloud copy `BACKEND_TO_POS.md` used; the two copies differ elsewhere). Related items: POS-BE-023 (pairing, Path B uses a staff JWT: `BACKEND_TO_POS.md:1866-1870,1944`), POS-BE-011 (`:1013`, text at `:1044-1046` says user JWTs are used by the till only for Path B's initial register call), POS-BE-022 (`:1796`) and POS-BE-030 (item heading `:2297` "READY (platform half)", text to about `:2313`; names `/api/auth/me`, `:2305`). The coordination files are among the uncommitted files of both repos; one hunk (line 2312) lies just inside the POS-BE-030 item, the others are outside the cited sections.

## Security considerations
- Throttling: two-axis login limiter (IP, account+IP) and change-password limiter (see Current behavior 9).
- Tokens carry no role/status; the guard re-reads the user on every request, so suspension and role changes apply immediately (`AppServiceProvider.php:232-239`).
- Passwords are hashed by the model cast; `role`, `role_id` and `restaurant_id` are not mass-assignable (`C:app/Models/User.php:28-39`; `C:tests/Feature/SecurityHardeningTest.php:197-224` (`role` and `restaurant_id`; `role_id` is not asserted)).
- Audit: login success, failure, blocked, logout and password change are recorded through `AuditLogger` (the daily activity file is the only sink: `AuditLogger::record` only calls `writeToActivityFile`, which returns early when `ACTIVITY_LOG_FILE` is false, so that setting silences these events entirely: `C:app/Services/AuditLogger.php:17-20,47,110-115`, `C:config/platform.php:195`; the config comment at `C:config/platform.php:190-193` still describes a database trail and is stale; the legacy `audit_logs` table has no writer in `app`, only `BackfillActivityLogs` reads it and `PruneAuditLogs` reads and deletes its rows).
- Failed-login audit lines include the attempted username (`AuthController.php:46-51`).
- The `User` model has no tenant scope; tenant isolation of users is by explicit queries (see `tenant-isolation`).

## Known limitations
- No refresh token and no server-side revocation (BR-8); consequences for a leaked token: `BEHAVIORAL_ANALYSIS.md` F.
- `remember` is a dead field; `LoginView` reads `errors.email[0]`, a key the login endpoint does not return (`W:src/pages/LoginView.vue:55-57`).
- No Vue page for the platform portal's password change (grep of `W:src/pages/admin`).
- The comment at `C:tests/Feature/ActivityLogFileTest.php:59` mentions a `last_login_at` write that does not exist.

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/AuthTest.php:15,24,33,42,56` (super admin login, case-insensitive username, wrong password 401, suspended 403, `me` context) | BR-2, BR-4 | the 422 body, `expires_in`, `token_type`, the 403 body, unknown `restaurant` slug |
| Cloud feature | `C:tests/Feature/PerTenantAuthTest.php:19-126` (9 tests: shared usernames, subdomain scoping, wrong host, admin host, slug precedence) | BR-1 (two same-username rows in different tenants coexist, `:19-28`), BR-3 | no test that a duplicate username within one tenant is rejected by the index (`grep users_username tests` → no match) |
| Cloud feature | `C:tests/Feature/JwtRoundTripTest.php:21,27,34,43` (no token, valid, forged payload, garbage) | guard basics | expired token, `rid` mismatch, suspended user with a real bearer token (`actingAs` bypasses the guard), logout |
| Cloud feature | `C:tests/Feature/ChangePasswordTest.php:15,39,51,63,75,86` | BR-7 and the new token | throttle `6,1` |
| Cloud feature | `C:tests/Feature/SecurityHardeningTest.php:30,44` (token before/after `password_changed_at`), `:154` (login limiter 5 wrong → 429) | BR-6, rate limit | same-second boundary |
| Cloud feature | `C:tests/Feature/AuditLogTest.php:74,84-88` (login and failed login audited; `:142` only issues a failed login as setup), `C:tests/Feature/ActivityLogFileTest.php:63-69` (login writes an `auth.login` line), `:97-107` (nothing written when the file is disabled) | login audit events | `auth.login_blocked`, `auth.logout`, `auth.password_changed` |
| Cloud feature | `C:tests/Feature/TenantRbacTest.php:176,185,408-443,445-456`, `C:tests/Feature/CapabilityVerbsTest.php:275-298`, `C:tests/Feature/Pos/PosPurchaseCapabilityWithheldTest.php:27`, `C:tests/Feature/Admin/PlatformUserTest.php:57` | suspended user refused by `EnsureRole`, wrong role 403, `/auth/me` capabilities, email-less staff login, platform user login | |
No Unit tests reference Jwt or auth (`grep -rn "Jwt\|auth" C:tests/Unit` → no match). All cloud tests run on SQLite `:memory:` with a test-only `JWT_SECRET` (`C:phpunit.xml:25-31`).
Test results: `TEST_REPORT.md`.

## Acceptance criteria
- AC-1: A user can sign in with the right username and password on the tenant they belong to and receives a Bearer token and the user resource.
- AC-2: Wrong credentials give 401; a suspended account with the right password gives 403.
- AC-3: The same username can exist in two restaurants and each signs in only on its own tenant; a restaurant admin cannot sign in on the super-admin host.
- AC-4: A request without a valid, unexpired, correctly bound token is refused with 401.
- AC-5: A token issued in an earlier second than the user's last password change is refused (`C:app/Providers/AppServiceProvider.php:248-249`).
- AC-6: Changing the password requires the current password, enforces the password policy, and returns a working new token.
- AC-7: Login is rate limited per IP and per account+IP.
- AC-8: Logout returns success without revoking the token.

## Confirmed source references
Cloud: `C:routes/api.php:87-96`; `C:app/Http/Controllers/Auth/AuthController.php`; `C:app/Http/Requests/Auth/{LoginRequest,ChangePasswordRequest}.php`; `C:app/Support/Jwt.php`; `C:config/jwt.php`; `C:config/auth.php`; `C:app/Providers/AppServiceProvider.php:175-182,219-254`; `C:app/Http/Middleware/{EnsureRole,SetLocale}.php`; `C:bootstrap/app.php:45-69`; `C:app/Http/Resources/UserResource.php`; `C:app/Models/User.php`; `C:app/Services/AuditLogger.php`.
Clients: `K:api-client/src/{auth,api}.js`; `W:src/pages/LoginView.vue`; `W:src/router/index.js:260-291`; `W:src/pages/dashboard/ProfileView.vue:120-140`; `P:lib/data/cloud/{cloud_api,cloud_provisioning_repository}.dart`.

## Unknowns and assumptions
- UNVERIFIED: PostgreSQL typing of the strict `rid` comparison (`AppServiceProvider.php:241`); the SQLite tests cannot show it.
- UNVERIFIED: production values of `JWT_SECRET`, `JWT_TTL`, `JWT_ALGO` (environment not read).
- The login 422 body shape is not asserted by any test.

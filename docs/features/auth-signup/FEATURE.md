# Feature specification: Self-service restaurant signup

Status: implemented on the cloud API, disabled unless a flag is on; no client found
Slug: `auth-signup` · Module: `auth-and-tenancy` · Footprint: cloud-only (no POS or Vue consumer found)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
`POST /api/public/signup` creates a restaurant on a trial, its owner account and a POS licence in one transaction and emails the owner a temporary password. The endpoint is hidden (404) unless `SELF_SERVE_SIGNUP` is enabled.

## Scope and exclusions
Implemented: the endpoint, its request validation, a honeypot field, slug generation, provisioning through `RestaurantProvisioningService`, the credentials email.
Not found: a Vue page or call for signup (case-insensitive grep over `A:landing/src`, `A:menu/src`, `W:src`, `K:` → no match); a POS consumer was not searched specifically (public endpoint).

## Actors and permissions
Anonymous caller; no auth middleware (`C:routes/api.php:841-842`, `throttle:5,10`). Feature flag: `config('platform.self_serve_signup')` (`C:config/platform.php:56`), enforced by `abort_unless(..., 404)` (`C:app/Http/Controllers/Public/SignupController.php:28`).

## Current implemented behavior
1. Flag off → 404 (`SignupController.php:28`).
2. Validation (`C:app/Http/Requests/Public/SignupRequest.php:18-22`): `restaurant_name` required string max 150; `restaurant_name_ar` nullable string max 150; `name` required string max 150; `email` required email max 255 unique in `users.email`; `whatsapp` nullable string max 40 with the `MobileNumber` rule (`C:app/Rules/MobileNumber.php:27`). There is no password or username field.
3. Honeypot: a filled `website` field returns 201 `{message}` and provisions nothing; it runs after validation (`SignupController.php:30-34`).
4. Slug: normalised restaurant name; an empty or reserved result is replaced by `r-` plus six random lower-case characters (`SignupController.php:41-44`); `RestaurantProvisioningService` makes it unique with numeric suffixes (`C:app/Services/RestaurantProvisioningService.php:73`). Reserved slugs: `C:config/platform.php:42-45`.
5. Provisioning input: status ACTIVE, subscription TRIAL, start today, end today plus `SIGNUP_TRIAL_DAYS` (default 14); no plan; admin `name` and `email` only (`SignupController.php:46-60`, `C:config/platform.php:57`).
6. In one `DB::transaction` (`RestaurantProvisioningService.php:108-150`): the restaurant; the owner (`forceCreate`, role `RESTAURANT_ADMIN`, `role_id` null, ACTIVE, `email_verified_at` and `password_changed_at` now, password hashed from a generated 16-character password, username derived from the slug); the system staff roles (`$this->roles->seedSystemRoles`, `:129`); no branch (`branchData` null); the feature rows (with no plan, `Feature::defaultSet()` applies: QR menu, WhatsApp ordering, pickup, delivery are on, the rest off) (`:84,136-137`, `C:app/Enums/Feature.php:86-95`, `C:app/Services/PlanEntitlementService.php:49-58`); and a POS licence through `LicenceIssuer` (`:143-147`).
7. After the transaction the owner is notified with `RestaurantAdminCredentials` (email and temporary password) (`:153`); the notification class is not queued (`C:app/Notifications/RestaurantAdminCredentials.php`).
8. Success → 201 `{data: {public_url, login_url, trial_days}, message}` (`SignupController.php:62-69`).

## User journeys and workflows
Anonymous visitor submits the form → owner receives an email with a temporary password → signs in (`auth-login`) at the returned login URL.

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | The endpoint exists only when `SELF_SERVE_SIGNUP` is on. | controller | `SignupController.php:28`; test `C:tests/Feature/SignupTest.php:28` |
| BR-2 | Email must be unique across all users. | request | `SignupRequest.php`; test `SignupTest.php:68` |
| BR-3 | A signup starts as ACTIVE on a TRIAL for `SIGNUP_TRIAL_DAYS` days. | controller | `SignupController.php:46-56`; test `SignupTest.php:35` |
| BR-4 | The owner's password is generated, not chosen. | provisioning | `RestaurantProvisioningService.php:63-69` |
| BR-5 | Restaurant, owner, roles, feature rows and licence are created together or not at all. | transaction | `RestaurantProvisioningService.php:108-150` |
| BR-6 | Reserved or empty slugs are replaced by a random handle. | controller | `SignupController.php:41-44` |
| BR-7 | A filled honeypot field returns success and creates nothing. | controller | `SignupController.php:32-34`; test `SignupTest.php:58` |

## Validation and error handling
See Current behavior 2. 404 flag off; 422 validation (standard shape, not under `api/pos/*`); 429 throttle (shape not tested, UNVERIFIED).

## Edge cases and failure handling
- Arabic-only names: the slug is transliterated (`C:tests/Feature/SignupTest.php:78`); the `r-xxxxxx` fallback is not exercised by any test.
- Signup default features exclude `pos` (see Current behavior 6); consequences for PIN and till features: `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
None found. The licence created here is consumed by the POS pairing flows (`pos-licensing`).

## Security considerations
- Public endpoint with `throttle:5,10`, a honeypot and a feature flag; email uniqueness check is a request rule (check-then-insert).
- The temporary password is emailed in clear text by design (`C:app/Notifications/RestaurantAdminCredentials.php`, body contains the password); `password_changed_at` is stamped at creation.
- Tenant isolation of the new data is by `restaurant_id` set in the provisioning code (`forceCreate`, `BelongsToRestaurant` stamping).

## Known limitations
- Hidden by default; no client in the repository.
- No branch and no terminal are created (docblock `RestaurantProvisioningService.php:40-45`).
- Roles seeded: the code comment says four system roles; `TenantRoleService::presets()` lists one preset (`admin`) (`C:app/Services/TenantRoleService.php:36-67`); the actual count was not reconciled.

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/SignupTest.php:28,35,58,68,78` | flag, happy path (201, slug, TRIAL, end date, owner, notification), honeypot, duplicate email, Arabic name | throttle, reserved slug, slug collision, `r-` fallback, invalid `whatsapp`, licence row created, rollback on licence failure, mail content |
| Cloud feature | `C:tests/Feature/RestaurantFeatureTest.php:197-213` | signup yields QR menu on and table management off | |
All need a database (SQLite); none skipped. The notification is faked in tests.

## Acceptance criteria
- AC-1: With the flag off the endpoint returns 404.
- AC-2: A valid request creates a restaurant on a trial, an owner and a licence and returns the public and login URLs.
- AC-3: A duplicate email is refused with 422.
- AC-4: A filled honeypot returns success without creating anything.
- AC-5: The slug is unique and never reserved.

## Confirmed source references
`C:routes/api.php:841-842`; `C:app/Http/Controllers/Public/SignupController.php`; `C:app/Http/Requests/Public/SignupRequest.php`; `C:app/Services/RestaurantProvisioningService.php`; `C:app/Services/SlugService.php`; `C:app/Notifications/RestaurantAdminCredentials.php`; `C:config/platform.php:42-57`; `C:app/Enums/Feature.php:86-95`.

## Unknowns and assumptions
- UNVERIFIED: the 429 response shape; mail delivery behavior; whether a unique index on `users.email` still exists after the nullable change.
- UNVERIFIED: `LicenceIssuer` defaults beyond `max_terminals` and modes (`RestaurantProvisioningService.php:210,215`).

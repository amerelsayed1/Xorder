# Feature specification: Password reset by email

Status: implemented on the cloud API; no web or POS client found
Slug: `auth-password-reset` · Module: `auth-and-tenancy` · Footprint: cloud-only (no POS or Vue consumer found)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
A user who knows the email on their account asks for a reset link (`forgot-password`) and then sets a new password with the emailed token (`reset-password`). Both endpoints are public and rate limited. The endpoints do not reveal whether an email exists.

## Scope and exclusions
Implemented: `POST /api/auth/forgot-password`, `POST /api/auth/reset-password` (`C:routes/api.php:88-89`), the reset URL builder, Laravel's stock reset mail notification and password broker.
Not found in code (recorded searches in `FEATURE_INVENTORY.md` "Absent"): a Vue route, page or API call for forgot/reset or for the `/reset-password` page the email links to; any POS use; a custom reset notification.
Admin-initiated resets of platform users, restaurant admins and staff are other features (`platform-users`, `staff-management`, `platform-restaurants`).

## Actors and permissions
| Actor | Rule | Enforced by | Evidence |
| --- | --- | --- | --- |
| Anyone | may request a link and submit a reset | no auth middleware; `throttle:5,1` on both routes | `C:routes/api.php:88-89` |
| Account holder | must control the email and hold a valid token | password broker | `C:app/Http/Controllers/Auth/PasswordResetController.php:19,37` |

## Current implemented behavior
1. `forgot`: validates `email` (required, email), calls `Password::sendResetLink`, ignores the returned status, and always returns 200 with the `reset_link_sent` message (`C:app/Http/Controllers/Auth/PasswordResetController.php:14-24`).
2. The reset mail is Laravel's stock `ResetPassword` notification; `User` has no override and `C:app/Notifications/` has no reset notification (`C:app/Models/User.php:20`).
3. The link is `{restaurant dashboard URL}/reset-password?token=...&email=...` for a user with a restaurant (`Restaurant::dashboardUrl('reset-password')`), or `{scheme}://{platform.menu_domain}[:port]/reset-password?...` for platform users, falling back to `app.url` when no menu domain is configured (`C:app/Providers/AppServiceProvider.php:88-109`, `C:app/Models/Restaurant.php:314-328`).
4. `reset`: validates `token` (required string), `email` (required email), `password` (required, confirmed, min 12, mixed case, numbers); on success sets the password (hashed by cast), `password_changed_at = now()` and a new `remember_token`, returns 200 `password_reset` message; any other broker status returns 422 with one generic `password_reset_failed` message (`PasswordResetController.php:26-60`).
5. Broker: `passwords.users` with table `password_reset_tokens`, expiry 60 minutes, per-user throttle 60 seconds (`C:config/auth.php:104-110`).
6. Mail transport is `MAIL_MAILER` (config default `log`); tests use the `array` mailer (`C:config/mail.php:17`, `C:phpunit.xml:25-31`).

## User journeys and workflows
Intended journey from the code: request link → open the emailed URL → submit token, email and a new password. The page at the emailed URL is not part of any app in the repository (see Scope).

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | The forgot response never depends on whether the email exists. | controller returns the same 200 | `PasswordResetController.php:18-23`; test `C:tests/Feature/SecurityHardeningTest.php:99` |
| BR-2 | Reset failures (unknown email, bad token) return one generic 422. | controller | `PasswordResetController.php:50-57`; test `SecurityHardeningTest.php:74` |
| BR-3 | A successful reset stamps `password_changed_at`, so earlier tokens are rejected by the guard. | controller callback + guard | `PasswordResetController.php:43-44`; `C:app/Providers/AppServiceProvider.php:245-251`; test `SecurityHardeningTest.php:55` |
| BR-4 | The new password must be at least 12 characters with mixed case and numbers, and confirmed. | request rules | `PasswordResetController.php:34`; test `SecurityHardeningTest.php:138` |
| BR-5 | Tokens expire after 60 minutes; the broker throttles repeat requests per user for 60 seconds. | broker config | `C:config/auth.php:104-110` |
| BR-6 | The broker finds the account by `users.email`, which is unique where present and nullable. | migrations | `C:database/migrations/0001_01_01_000000_create_users_table.php:17`; `C:database/migrations/2026_07_21_000200_add_username_to_users_table.php:40` |

## Validation and error handling
| Situation | Check | Result | Evidence |
| --- | --- | --- | --- |
| forgot with bad body | `email` required|email | 422 (Laravel default shape) | `PasswordResetController.php:16` |
| forgot, any account state | none visible | 200 generic | `:18-23` |
| reset weak/unconfirmed password | rules above | 422 | `:28-35` |
| reset bad token or unknown email | broker status | 422 generic message | `:50-57` |
| too many requests | `throttle:5,1` | 429 (framework default); not tested | `C:routes/api.php:88-89` |

## Edge cases and failure handling
- Accounts without an email (staff created with a username only, `C:tests/Feature/TenantRbacTest.php:449-458`) have nothing for the broker to match.
- The forgot endpoint ignores the broker's throttled status and still answers 200 (`PasswordResetController.php:19`).
- Consequences and flows involving mail delivery and link reuse: `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
None found: no POS call and no Vue call to either endpoint (`grep -rniE "forgot|auth/reset|reset-password" W:src A:landing/src A:menu/src K:` → only admin-initiated reset calls of other features).

## Security considerations
- No account enumeration through response bodies or status codes (BR-1, BR-2; tests above).
- Reset invalidates older bearer tokens (BR-3).
- Only the action is logged for password changes elsewhere; no audit event is written by these two endpoints (`PasswordResetController.php` has no `AuditLogger` call).
- The throttle is the framework default key; effect per IP or per user: `BEHAVIORAL_ANALYSIS.md`.

## Known limitations
- No client page for the emailed link in this repository.
- Accounts without an email cannot use this flow.
- The reset mail is the framework's stock text and is not localised by this code (no custom notification).

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/SecurityHardeningTest.php:55` (reset stamps `password_changed_at`), `:74` (generic failure), `:99` (forgot is not an oracle; token row exists for the real email), `:119` (link contains `/reset-password`, `token=` and the urlencoded email; it does not assert the host or slug despite its name), `:138` (weak password 422) | BR-1..4 | throttle (`5,1`), token expiry, token reuse, 429 body, mail sent for platform users, locale of the mail |
No Unit tests. Tests need a database (SQLite `:memory:`), none skipped.

## Acceptance criteria
- AC-1: Requesting a reset link returns the same 200 response for existing and non-existing emails.
- AC-2: Resetting with a valid token and a compliant password sets the password and invalidates older bearer tokens.
- AC-3: A bad token or unknown email returns one generic 422.
- AC-4: A non-compliant new password is refused with 422.
- AC-5: Both endpoints are rate limited.

## Confirmed source references
`C:routes/api.php:88-89`; `C:app/Http/Controllers/Auth/PasswordResetController.php`; `C:app/Providers/AppServiceProvider.php:88-109`; `C:app/Models/Restaurant.php:314-328`; `C:config/auth.php:104-110`; `C:config/mail.php:17`; `C:app/Models/User.php`; `C:tests/Feature/SecurityHardeningTest.php`.

## Unknowns and assumptions
- UNVERIFIED: production mail transport and delivery (environment not read).
- UNVERIFIED: whether the stock notification is queued (the class was not read; the vendor code was not traced).
- UNVERIFIED: whether a webserver rule or page serves `/reset-password` on the dashboard hosts.
- UNVERIFIED: broker deletion of used tokens (vendor code not read).

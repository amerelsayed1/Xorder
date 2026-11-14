# Technical design: Password reset by email

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
`PasswordResetController` → Laravel `Password` broker (`passwords.users`) → `ResetPassword` notification with a URL from `ResetPassword::createUrlUsing` (`C:app/Providers/AppServiceProvider.php:88-109`).

## Cloud implementation
| Layer | Files |
| --- | --- |
| Routes | `C:routes/api.php:88-89` |
| Controller | `C:app/Http/Controllers/Auth/PasswordResetController.php` |
| URL builder | `C:app/Providers/AppServiceProvider.php:88-109`, `C:app/Models/Restaurant.php:314-328` (`dashboardUrl`) |
| Config | `C:config/auth.php:104-110`, `C:config/mail.php:17`, `C:config/platform.php` (`menu_domain`) |

## Web frontend implementation
None.

## Desktop POS implementation
None.

## Source references
See `FEATURE.md`.

## State and data flow
Token rows live in `password_reset_tokens`; a successful reset updates `users`.

## Local persistence and caching
None.

## Offline operation and synchronization
Not applicable.

## Dependencies
Laravel password broker and mail. Configuration keys by name: `MAIL_MAILER`, `AUTH_PASSWORD_RESET_TOKEN_TABLE`, `platform.menu_domain`.

## Failure handling and observability
Generic messages by design; no audit event; mail transport failures are not handled in the controller.

## Platform-specific behavior
None.

## Compatibility and rollout
Cloud deploys by push to `main`; the emailed URL format depends on `platform.menu_domain` and the restaurant slug.

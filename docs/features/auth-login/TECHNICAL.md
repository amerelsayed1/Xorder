# Technical design: Login, session token and password change

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
Controller `AuthController` → `LoginRequest`/`ChangePasswordRequest` → Eloquent user provider → `Jwt::issue`; later requests pass through the `jwt` guard (`Auth::viaRequest`) and, on dashboard/admin routes, `EnsureRole`.

## Cloud implementation
| Layer | Files | Responsibility |
| --- | --- | --- |
| Routes | `C:routes/api.php:86-96` | auth group, throttles |
| Controller | `C:app/Http/Controllers/Auth/AuthController.php` | login, logout, me, change-password |
| Requests | `C:app/Http/Requests/Auth/LoginRequest.php`, `ChangePasswordRequest.php` | validation |
| Token | `C:app/Support/Jwt.php`, `C:config/jwt.php` | issue/parse |
| Guard | `C:app/Providers/AppServiceProvider.php:217-255` | bearer → user |
| Limiter | `AppServiceProvider.php:175-182` | `throttle:login` |
| Middleware | `C:app/Http/Middleware/EnsureRole.php`, `SetLocale.php`; `C:bootstrap/app.php:45-69` | role/status gate, locale, JSON, headers, trusted proxies |
| Audit | `C:app/Services/AuditLogger.php` | login/logout/password events |

## Web frontend implementation
| App | Files | Notes |
| --- | --- | --- |
| `apps/web` | `W:src/pages/LoginView.vue`, `W:src/router/index.js:260-291` (guard), `W:src/lib/host.js`, `W:src/pages/dashboard/ProfileView.vue:120-140` | slug derived from host; redirect by role |
| shared client | `K:api-client/src/auth.js`, `K:api-client/src/api.js` | token storage, headers, 401 handling |

## Desktop POS implementation
`P:lib/data/cloud/cloud_api.dart:94-104` (`login`), `P:lib/data/cloud/cloud_provisioning_repository.dart:82,226,297` (callers). Used only while pairing a till.

## Source references
See `FEATURE.md` "Confirmed source references".

## State and data flow
State is the token on the client and `users` (status, role, `password_changed_at`) on the server; the guard reads the user on every request.

## Local persistence and caching
POS: none (token not stored). Web: `localStorage` key `xorder_token`.

## Offline operation and synchronization
Not applicable.

## Dependencies
`firebase/php-jwt`, Laravel password hashing and rate limiter. Configuration keys by name: `JWT_SECRET`, `JWT_TTL`, `JWT_ALGO`.

## Failure handling and observability
Messages come from `lang` files (`C:lang/{en,ar}/xorder.php`, `C:lang/ar/auth.php`); audit events are written to a daily activity file, the only sink (`C:app/Services/AuditLogger.php:12-21`); English `auth.failed` comes from the framework's own language file (there is no `lang/en/auth.php`).

## Platform-specific behavior
None found in the cloud code; POS login is platform-independent.

## Compatibility and rollout
Cloud deploys by push to `main` (production); response keys read by the clients: `token`, `data` (SPA) and `token` and a `data.restaurant.name` that the response does not carry (POS, `P:lib/data/cloud/cloud_provisioning_repository.dart:101,127-130`; see `API.md` Backward compatibility).

# API contract: Login, session token and password change

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

No `/v1` prefix; all paths under `/api`. Route table: `docs/architecture/cloud-route-index.md`. Locale: `X-Locale` header or `lang` query (`ar`/`en`).

## Producers and consumers
| Endpoint | Producer | Consumers |
| --- | --- | --- |
| `POST /api/auth/login` | `C:app/Http/Controllers/Auth/AuthController.php:24-82` | `K:api-client/src/auth.js:75`; `P:lib/data/cloud/cloud_api.dart:98`; `P:integration_test/support/e2e_platform.dart:64` (test helper) |
| `POST /api/auth/logout` | `AuthController.php:116-129` | `K:api-client/src/auth.js:99` |
| `GET /api/auth/me` | `AuthController.php:132-137` | `K:api-client/src/auth.js:88` |
| `POST /api/auth/change-password` | `AuthController.php:145-169` | `K:api-client/src/auth.js:109` |

## Verified endpoints
| Method | Path | Middleware | Controller@method | Route |
| --- | --- | --- | --- | --- |
| POST | `/api/auth/login` | `throttle:login` | `AuthController@login` | `C:routes/api.php:87` |
| POST | `/api/auth/logout` | `auth:jwt` | `@logout` | `:92` |
| GET | `/api/auth/me` | `auth:jwt` | `@me` | `:93` |
| POST | `/api/auth/change-password` | `auth:jwt`, `throttle:6,1` | `@changePassword` | `:95-96` |

## Authentication and authorization
Login is unauthenticated. The other three require a valid bearer token (`auth:jwt`, guard at `C:app/Providers/AppServiceProvider.php:219-254`); there is no role or capability gate on them.

## Request and response examples (redacted)
### `POST /api/auth/login`
Rules (`C:app/Http/Requests/Auth/LoginRequest.php:16-25`): `username` required|string|max:150, `password` required|string, `remember` sometimes|boolean, `restaurant` sometimes|nullable|string|max:255.
Success 200 keys: `data` (user resource), `token`, `token_type` = "Bearer", `expires_in` (seconds), `message` (`AuthController.php:75-81`). User resource keys: id, name, username, email, role, restaurant_id, status, is_owner, role_id, role_name, role_name_ar, capabilities, restaurant (`C:app/Http/Resources/UserResource.php:15-38`).
```json
{"data":{"id":1,"username":"manager","role":"RESTAURANT_ADMIN"},"token":"<jwt>","token_type":"Bearer","expires_in":604800,"message":"..."}
```
(Fake values; key set from the code; `expires_in` = default TTL 10080 minutes × 60.)
### `POST /api/auth/change-password`
Rules (`C:app/Http/Requests/Auth/ChangePasswordRequest.php:25-38`): `current_password` required|string|(must match the stored hash); `password` required|confirmed|different:current_password|min 12, mixed case, numbers. Success 200 keys: `token`, `token_type`, `expires_in`, `message` (`AuthController.php:163-168`).
### `GET /api/auth/me`, `POST /api/auth/logout`
`me` → `{"data": <user resource>}`; `logout` → `{"message": ...}`.

## Error formats
| Case | Status | Body | Evidence |
| --- | --- | --- | --- |
| wrong credentials | 401 | `{message}` (`auth.failed`) | `AuthController.php:52` |
| suspended account | 403 | `{message}` (`account_suspended`) | `:63` |
| no/invalid token | 401 | framework unauthenticated response | guard returns null |
| wrong role (dashboard/admin routes) | 401 no user (this includes a suspended account on a bearer request: the `jwt` guard returns no user for a non-ACTIVE account, `C:app/Providers/AppServiceProvider.php:233-237`); 403 `no_access` for a wrong role; 403 suspended only when a user is injected without the guard (as `actingAs` does) | `message` | `C:app/Http/Middleware/EnsureRole.php:20-30` |
| validation | 422 | Laravel error bag (asserted for change-password: `C:tests/Feature/ChangePasswordTest.php:48,60,72`; not asserted for login); the login 422 is not wrapped in the POS envelope because the route is not under `api/pos/*` (`C:bootstrap/app.php:75-85`) | |
| throttled | 429 | framework default | `C:tests/Feature/SecurityHardeningTest.php:154-171` |

## Idempotency, retries and concurrency
None defined: each login signs a new token (the payload has no `jti`, `C:app/Support/Jwt.php:26-35`, so two logins by one user within the same second return an identical token); change-password is not idempotent.

## POS and other client usage
| Client call site | Endpoint | Notes |
| --- | --- | --- |
| `P:lib/data/cloud/cloud_api.dart:98-104` | `POST /api/auth/login` body `{restaurant, username, password}` | token not stored; used for one to two follow-up calls per flow (see `FEATURE.md` cross-application section; the comment at `:92-93` says one call) |
| `K:api-client/src/auth.js:75-109` | login, me, logout, change-password | token in `localStorage` |

## Backward compatibility
No version prefix; no ledger item names `/api/auth/login`; POS-BE-030 names `/api/auth/me` (`apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:2305`); see `FEATURE.md` cross-application section. Adding response keys is additive; the SPA and the POS read `token` and `data`; the POS also reads `data.restaurant.name` (`P:lib/data/cloud/cloud_provisioning_repository.dart:101,127-130`), but the login response's `data.restaurant` is a `RestaurantResource` (loaded at `C:app/Http/Controllers/Auth/AuthController.php:66`) whose keys include `name_ar` and `name_en` and no `name` (`C:app/Http/Resources/RestaurantResource.php:22-23`; the only `'name'` in that file is `admin.name`, `:77`), so on this evidence the POS never finds a name there and shows its fallback (`tenantName ?? slug`, `:175`); the POS code comment says the display name rides the login response. Not run.

## Contract tests
| Test | Covers | Gaps |
| --- | --- | --- |
| `C:tests/Feature/AuthTest.php:15-56` | login 200/401/403, `me` | key sets, 422 |
| `C:tests/Feature/ChangePasswordTest.php:15-86` | change-password 200/422 (validation errors asserted)/401 | response keys |
| `C:tests/Feature/JwtRoundTripTest.php:21-43` | bearer handling | expiry, `rid` |

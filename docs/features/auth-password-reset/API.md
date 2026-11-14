# API contract: Password reset by email

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
| Endpoint | Producer | Consumers |
| --- | --- | --- |
| `POST /api/auth/forgot-password` | `C:app/Http/Controllers/Auth/PasswordResetController.php:14-24` | none found |
| `POST /api/auth/reset-password` | `PasswordResetController.php:26-60` | none found |

## Verified endpoints
| Method | Path | Middleware | Controller@method | Route |
| --- | --- | --- | --- | --- |
| POST | `/api/auth/forgot-password` | `throttle:5,1` | `PasswordResetController@forgot` | `C:routes/api.php:88` |
| POST | `/api/auth/reset-password` | `throttle:5,1` | `PasswordResetController@reset` | `C:routes/api.php:89` |

## Authentication and authorization
Unauthenticated. The reset token is the credential for `reset-password`.

## Request and response examples (redacted)
`forgot-password` body `{"email": "user@example.com"}` → 200 `{"message": "..."}` (always).
`reset-password` body `{"token": "<token>", "email": "user@example.com", "password": "<new>", "password_confirmation": "<new>"}` → 200 `{"message": "..."}` or 422 `{"message": "..."}` (generic) or 422 validation errors (`PasswordResetController.php:28-35,50-59`).

## Error formats
Validation: Laravel error bag (not under `api/pos/*`, so not wrapped in the POS envelope, `C:bootstrap/app.php:75-85`). Failure: 422 `{message}`. Throttle: 429 framework default.

## Idempotency, retries and concurrency
A reset token is consumed by the broker on success; replay behavior is not traced (UNVERIFIED).

## POS and other client usage
None found.

## Backward compatibility
No contract-ledger item; additive changes only.

## Contract tests
| Test | Covers | Gaps |
| --- | --- | --- |
| `C:tests/Feature/SecurityHardeningTest.php:55,74,99,119,138` | status codes, generic messages, link content | 429, expiry, replay |

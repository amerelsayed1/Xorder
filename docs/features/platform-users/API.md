# API contract: Platform (Super Admin portal) users

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
`/api/admin/users*` — producer `C:app/Http/Controllers/Admin/PlatformUserController.php`; consumers `W:src/pages/admin/UsersList.vue:19,46,71`, `UserForm.vue:32,50,55`.

## Verified endpoints
| Method | Path | Middleware (after `auth:jwt`, platform `role:`) | Controller@method | Route |
| --- | --- | --- | --- | --- |
| GET | `/api/admin/users` | `can:platform_users.manage` | `index` | `C:routes/api.php:140` |
| POST | `/api/admin/users` | same | `store` | `:141` |
| GET | `/api/admin/users/{user}` | same | `show` | `:142` |
| PUT | `/api/admin/users/{user}` | same | `update` | `:143` |
| DELETE | `/api/admin/users/{user}` | same | `destroy` | `:144` |
| POST | `/api/admin/users/{user}/reset-password` | same + `throttle:10,1` | `resetPassword` | `:145` |

## Authentication and authorization
Super Admin only (matrix). Target guards in `FEATURE.md`.

## Request and response examples (redacted)
`POST` body `{"name","username","email","role":"SALES","status?","password?"}` → 201 `{"data": <user resource>, "generated_password": "<string|null>", "message"}`. `reset-password` → `{"generated_password","message"}`. `DELETE` → `{"message"}`.

## Error formats
404 `platform_user_not_found`; 403 `platform_user_super_admin_forbidden`, `platform_user_self_forbidden`; 422 validation (`role` outside the assignable set, duplicate username/email).

## Idempotency, retries and concurrency
None.

## POS and other client usage
None.

## Backward compatibility
None recorded in the contract ledger.

## Contract tests
`C:tests/Feature/Admin/PlatformUserTest.php`, `C:tests/Feature/UserCreationMatrixTest.php`.

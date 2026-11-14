# API contract: Restaurant staff accounts

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
| Endpoint group | Producer | Consumers |
| --- | --- | --- |
| `/api/dashboard/staff*` (six routes; `staff/{staff}/pin` belongs to `pos-pin`) | `C:app/Http/Controllers/Dashboard/StaffController.php` | `W:src/pages/dashboard/StaffView.vue:27,72,187`, `StaffForm.vue:31,34,54-58` (also `GET roles` and `GET staff/{id}`) |
| bootstrap `staff[]` | `C:app/Services/PosBootstrapService.php:305-336` | `P:lib/data/cloud/bootstrap_bundle.dart:514-531`, `bootstrap_seeder.dart:459-507` |

## Verified endpoints
| Method | Path | Middleware (after `auth:jwt`, `role:<tenant roles>`) | Controller@method | Route |
| --- | --- | --- | --- | --- |
| GET | `/api/dashboard/staff` | `can:staff.view` | `index` | `C:routes/api.php:306` |
| GET | `/api/dashboard/staff/{staff}` | `can:staff.view` | `show` | `:307` |
| POST | `/api/dashboard/staff` | `can:staff.view`, `subscription.writable`, `can:staff.create` (+ `StoreStaffRequest`) | `store` | `:316` |
| PUT | `/api/dashboard/staff/{staff}` | `can:staff.view`, `subscription.writable`, `can:staff.update` | `update` | `:317` |
| DELETE | `/api/dashboard/staff/{staff}` | `can:staff.view`, `subscription.writable`, `can:staff.delete` | `destroy` | `:318` |
| POST | `/api/dashboard/staff/{staff}/reset-password` | as update + `throttle:10,1` | `resetPassword` | `:320-322` |

## Authentication and authorization
See `FEATURE.md` Actors. The `{staff}` parameter binds `User` without a tenant scope; the controller guard filters.

## Request and response examples (redacted)
`POST` body: `name`, `username`, `email?`, `role_id`, `status?`, `password?`. 201: `{"data": <user resource>, "generated_password": "<string|null>", "message": "..."}`. Plan limit: 422 `{"message": "..."}`. `PUT`: `{"data", "message"}`. `reset-password`: `{"generated_password", "message"}`. `DELETE`: `{"message"}`. User resource keys: see `auth-login` API.

## Error formats
Bodies carry a localized `message` only: 404 from `xorder.messages.staff_not_found`, 403 from `xorder.messages.staff_self_forbidden` (`StaffController.php:162,166`); 403 `xorder.errors.no_access` / `account_suspended` from `EnsureRole`; 422 validation errors (field keys such as `role_id`, `username`, `email`) or the plan-limit `{message}`; 403 from `subscription.writable` (`{message}`, plus `code: subscription_inactive` for the subscription case). The `can:` middleware denial body was not read.

## Idempotency, retries and concurrency
No idempotency key; create is not idempotent. Uniqueness is a request rule (`Rule::unique`) plus the database index.

## POS and other client usage
Bootstrap row keys `id, name, username, role_id, capabilities, is_active, pin` (`PosBootstrapService.php:305-336`); POS parses `id` and `name` as required and defaults `username` to `user-<id>` (`P:lib/data/cloud/bootstrap_bundle.dart:514-531`); `BootstrapStaff` has no `role_id` field and the seeder does not write `pos_staff.role_id` (`P:lib/data/cloud/bootstrap_bundle.dart:492-531`, `P:lib/data/cloud/bootstrap_seeder.dart:465-470`), although the cloud sends it (`C:app/Services/PosBootstrapService.php:321`); a POS code comment says `role_id` is not in the bundle (`P:lib/data/postgres/postgres_admin_repositories.dart:535`).

## Backward compatibility
The `capabilities` array in the bootstrap includes legacy `*.manage` aliases (`C:app/Models/User.php:134-145,167-183`); the code comment asks to remove them one release after the verb split.

## Contract tests
`C:tests/Feature/TenantRbacTest.php`, `UserCreationMatrixTest.php`, `PlanStaffLimitTest.php`; POS `P:test/data/cloud_bootstrap_test.dart:145-150`.

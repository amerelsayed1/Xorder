# API contract: Roles, capabilities and gates

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
| Endpoint group | Producer | Consumers |
| --- | --- | --- |
| `/api/dashboard/roles*` | `C:app/Http/Controllers/Dashboard/RoleController.php` | `W:src/pages/dashboard/RolesView.vue`, `RoleForm.vue` |
| `/api/auth/me` capabilities | `C:app/Http/Resources/UserResource.php:15-38` | `K:api-client/src/auth.js` |
| bootstrap `staff[].capabilities` | `C:app/Services/PosBootstrapService.php:305-336` | `P:lib/data/cloud/bootstrap_seeder.dart:465-487` |

## Verified endpoints
| Method | Path | Middleware after `auth:jwt`, `role:<tenant roles>` | Controller@method | Route |
| --- | --- | --- | --- | --- |
| GET | `/api/dashboard/roles` | `can:staff.view` | `index` | `C:routes/api.php:303` |
| GET | `/api/dashboard/roles/capabilities` | `can:staff.view` | `capabilities` | `:304` |
| GET | `/api/dashboard/roles/{role}` | `can:staff.view` | `show` | `:305` |
| POST | `/api/dashboard/roles` | `can:staff.view`, `subscription.writable`, `can:staff.create` | `store` | `:312` |
| PUT | `/api/dashboard/roles/{role}` | `... can:staff.update` | `update` | `:313` |
| DELETE | `/api/dashboard/roles/{role}` | `... can:staff.delete` | `destroy` | `:314` |

## Authentication and authorization
See `FEATURE.md`. Gate names equal capability values (`can:staff.view` etc.).

## Request and response examples (redacted)
`POST` body `{"name": "Cashier", "name_ar": null, "capabilities": ["orders.update", "menu.view"]}` → 201 `{"data": {id, name, name_ar, slug, is_system, capabilities, users_count?}, "message": "..."}` (`C:app/Http/Resources/RoleResource.php:14-24`; `users_count` appears only when counted, i.e. on index/show). `DELETE` with a role in use carries the request body `{"reassign_to": <id>}`: the SPA passes it as the axios `data` option (`W:src/pages/dashboard/RolesView.vue:125-127`), the controller reads `reassign_to` from the input (`RoleController.php:102`) and the test sends the same body (`TenantRbacTest.php:381`). `GET roles/capabilities` → `{"data": [{value, group, resource, action, implies}]}` for 40 cases (`RoleController.php:46-60`).

## Error formats
422 `{message}` for system role, role in use (`users_count`), plus validation errors on `capabilities`, `name`; 404 other tenant; 403 gates. Request validation uses the Laravel error bag.

## Idempotency, retries and concurrency
None.

## POS and other client usage
Bootstrap `capabilities`: `tenantCapabilities()` minus `purchase.manage` (`PosBootstrapService.php:322-331`); how the till maps them: `FEATURE.md` POS paragraph. Endpoint `GET roles/capabilities` is named in the ledger request for POS-BE-002 (`apps/xorder-cloud/docs/coordination/POS_TO_BACKEND.md:183`); no POS client call to it was found (`grep "roles/capabilities" apps/xorder-pos/lib` → see inventory "Absent").

## Backward compatibility
`User::tenantCapabilities()` appends legacy aliases through `withLegacyAliases` for the owner and for staff (`C:app/Models/User.php:134-145`); `UserResource` returns that list as `capabilities` (`C:app/Http/Resources/UserResource.php:36`) and `PosBootstrapService` sends it minus `purchase.manage` (`:322-331`). Requests with legacy values are refused (`C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php:27-30`).

## Contract tests
`C:tests/Feature/TenantRbacTest.php`, `CapabilityVerbsTest.php:271-294` (aliases in `/auth/me`), `UserCreationMatrixTest.php`.

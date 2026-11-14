# API contract: Tenant isolation (restaurant scope)

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

No endpoints of its own. Observable behavior: cross-tenant resources return 404 on scoped models and on the staff/PIN guards; tenant users cannot reach admin routes (403) (`C:tests/Feature/TenantIsolationTest.php:16`). Route index: `docs/architecture/cloud-route-index.md`.

## Producers and consumers
Applies to every `auth:jwt` dashboard route and every `pos.device` route.

## Verified endpoints
See the route index; this feature has none.

## Authentication and authorization
Tenant comes from the bearer token's user (`rid` claim checked by the guard, `auth-login`) or from the device token (`PosDeviceAuth`).

## Request and response examples (redacted)
Not applicable.

## Error formats
404 with `message` (`staff_not_found`) or the framework's model-not-found response.

## Idempotency, retries and concurrency
Not applicable.

## POS and other client usage
POS requests get their tenant from the terminal row (`C:app/Http/Middleware/PosDeviceAuth.php:54-77`).

## Backward compatibility
Not applicable.

## Contract tests
`C:tests/Feature/TenantIsolationTest.php`, `C:tests/Feature/TenantRbacTest.php:243,389,564`.

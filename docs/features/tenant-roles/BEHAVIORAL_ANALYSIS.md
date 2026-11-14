# Behavioral analysis: Roles, capabilities and gates

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Legacy aliases ride into POS capabilities
- Claim: see staff-management analysis F
- Trace: `C:app/Models/User.php:167-183`, `PosBootstrapService.php:328-331`, `P:lib/domain/models/permissions.dart:238`
- Confidence: medium. Would be confirmed by: a POS test

## B. Existing restaurants' protected Admin role may lack newer capabilities
- Claim: migration 000100 froze 28 verbs; no later migration adds `pos.*`, `customers.create`, `purchase.manage`; only newly provisioned restaurants get `Cap::cases()`
- Trace: `C:database/migrations/2026_08_22_000100_create_roles_table.php:73-86`, `C:app/Services/TenantRoleService.php:42,64`; production data not readable here
- Confidence: medium. Would be confirmed by: a read-only query of production `roles` (not permitted)

## C. Role delete reassignment has no above-self check
- Claim: a limited manager with `staff.delete` might move holders onto a stronger role
- Trace: `C:app/Http/Controllers/Dashboard/RoleController.php:93-130` vs `StoreStaffRequest.php:48`
- Confidence: medium. Would be confirmed by: a feature test with a limited actor

## D. The protected Admin role can be narrowed
- Claim: update has no `is_system` guard
- Trace: `UpdateRoleRequest.php`, `TenantRoleService.php:92-104`, `C:app/Models/Role.php:16-17`
- Confidence: high for the path; effect depends on assignments. Would be confirmed by: a PUT test

## E. Suspended accounts: 401 versus 403
- Claim: a real bearer request for a suspended user fails in the guard (401) before `EnsureRole` (403); tests use `actingAs`
- Trace: `AppServiceProvider.php:237`, `EnsureRole.php:24-26`, `C:tests/Feature/TenantRbacTest.php:176`
- Confidence: medium. Would be confirmed by: a bearer-token test

## F. Pulse counts versus `live.view`
- Claim: pulse checks `orders.view`/`bills.view` while lists accept `orders.read`/`bills.read`; a live-view-only role sees null counts
- Trace: `C:app/Http/Controllers/Dashboard/PulseController.php:34,38`, `AppServiceProvider.php:161-163`
- Confidence: medium. Would be confirmed by: a test

## G. Weak assertions in `UserCreationMatrixTest`
- Claim: `holdsTenantCapability` is called with three arguments (`:201`, `:276`); only the first counts
- Trace: `C:tests/Feature/UserCreationMatrixTest.php:201,276`, `User.php:115`
- Confidence: high, low impact. Would be confirmed by: n/a

## H. Missing language keys
- Claim: 30 of 40 capability values have no `xorder.capabilities.*` entry, so the above-self message prints the raw key for them
- Trace: `C:lang/en/xorder.php:333-352`
- Confidence: medium (framework fallback assumed). Would be confirmed by: a test of the message

## I. Role edits and bootstrap freshness on tills
- Claim: role create/update/delete and role reassignment do not bump `restaurants.pos_config_version` (not in the hook list, `PosConfigVersion.php:55-58`; KNOWN GAP comment `:27-31`), the bootstrap answers 304 for an unchanged ETag, and the seeder skips equal versions, so a till may keep old capabilities until another change bumps the version or the heartbeat reports a newer one (heartbeat refresh was not traced)
- Also: `reassignRole` uses a query-builder `update` (`TenantUserService.php:108-114`), which in Laravel does not fire per-model events, so holders' role change is probably not audited per user; the move and the delete are two statements without a transaction
- Trace: `C:app/Http/Controllers/Pos/BootstrapController.php:25-33`, `P:lib/data/cloud/bootstrap_seeder.dart:71-76`, `C:app/Http/Controllers/Dashboard/RoleController.php:93-130`
- Confidence: medium. Would be confirmed by: a test changing a role then fetching the bootstrap with the old ETag

## J. Role or status change applies on the next cloud request, not on the till
- Claim: the cloud guard reads the user each request so cloud gates follow role changes immediately, while the till uses its stored `pos_staff.capabilities` (see I)
- Trace: `AppServiceProvider.php:217-255`, `P:lib/data/cloud/bootstrap_seeder.dart:465-487`
- Confidence: medium

## K. What adding a capability touches
- Claim: enum case, implications, route gates, Vue labels, language keys, POS mapping and a data migration for existing roles (the last because no migration backfills newer capabilities)
- Trace: inferred from `TenantCapability.php`, `W:src/lib/capabilities.js`, `lang/en/xorder.php:333-352`, `P:lib/domain/models/permissions.dart:222-266`; not checked as a list
- Confidence: low


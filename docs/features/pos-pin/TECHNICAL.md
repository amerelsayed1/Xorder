# Technical design: Cashier PIN for the POS

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Architecture and modules
Dashboard → `PosPinController` → `PosPin` → `users` columns → `PosConfigVersion::bump`; till → bootstrap → `pos_staff` → `PinHash.verify`.

## Cloud implementation
| Layer | Files |
| --- | --- |
| Routes | `C:routes/api.php:705-711` |
| Controller / request | `C:app/Http/Controllers/Dashboard/PosPinController.php`, `C:app/Http/Requests/Dashboard/SetPosPinRequest.php` |
| Hashing | `C:app/Support/PosPin.php` |
| Delivery | `C:app/Services/PosBootstrapService.php:305-336` |
| Config version | `C:app/Services/PosConfigVersion.php` (auto-bump hooks list at `:55` covers Branch, TaxRule, Charge, TenderType, PosTerminal, ReceiptProfile) |

## Web frontend implementation
`W:src/pages/dashboard/StaffView.vue:114-167`.

## Desktop POS implementation
`P:lib/core/security/pin_hash.dart`, `P:lib/data/postgres/postgres_directory_repositories.dart:164,244,447`, `P:lib/features/lock/lock_screen.dart`, `P:lib/features/admin/presentation/management_staff_pane.dart:1367-1368,1536-1538`, `P:lib/data/postgres/local_bootstrap.dart:590-591` (owner PIN at install).

## Source references
See `FEATURE.md`.

## State and data flow
Verifier stored cloud-side, copied to tills at bootstrap, verified locally.

## Local persistence and caching
POS `pos_staff`.

## Offline operation and synchronization
Verification is local; verifier updates arrive with the bootstrap; timing: `BEHAVIORAL_ANALYSIS.md`.

## Dependencies
PHP `hash_pbkdf2`; Dart `cryptography` (Pbkdf2).

## Failure handling and observability
Audit `staff.pos_pin_set` / `staff.pos_pin_cleared`.

## Platform-specific behavior
None.

## Compatibility and rollout
Changing algorithm or iterations requires a coordinated cloud and POS change.

# Module: shifts-and-cash

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`
Status: partially documented (1 of 2 features drafted) · Footprint: shared

## Purpose and scope
Cashier sessions on a till, the cash that moves in and out of the drawer, the cash-up at close, and refunds that leave the drawer. The POS records first; the cloud recomputes and displays. Cloud-side review of shifts beyond the dashboard "current shift" tiles does not exist (see `docs/features/pos-shifts/FEATURE.md`).

## Features
| Slug | Title | Footprint | Status | Docs |
| --- | --- | --- | --- | --- |
| `pos-shifts` | Shifts, cash movements, cash-up | shared | drafted | `docs/features/pos-shifts/` |
| `pos-refunds` | Refunds (cash refunds enter expected cash) | UNVERIFIED | pending | — |

## Actors and permissions
Cloud `TenantCapability` `pos.shift_open`, `pos.shift_close`, `pos.cash_movement` (`apps/xorder-cloud/apps/api/app/Enums/TenantCapability.php:98-100`, checked only when `acting_user_id` is sent); POS `shift.open` (UI check), `shift.close`, `cash.movement`, `cash.open_without_sale` (`apps/xorder-pos/lib/domain/models/permissions.dart:63-72`). Refund permissions: pending (`pos-refunds`).

## Architecture of the module
Cloud: `Pos\ShiftController` → `PosShiftService` → `PosShift`, `PosCashMovement`; refunds `Pos\RefundController` → `PosRefundService` (not yet traced). POS: `ShiftRepository` → `PostgresShiftRepository`; sync through `outbox_drain.dart`. Details in the feature docs.

## Data
Cloud `pos_shifts`, `pos_cash_movements`, `pos_refunds*`; POS `pos_shifts`, `pos_cash_movements`, `pos_sync_outbox`.

## Cross-application dependencies
Contract POS-BE-009 (READY), POS-BE-010 (refunds, cash term in expected cash). Outbox phase order within a pass: customers → shift open → orders → cash movements and refunds → shift close (`apps/xorder-pos/lib/data/cloud/outbox_drain.dart:280-296`; a pass stops after a phase that reports offline; see `docs/features/pos-shifts/BEHAVIORAL_ANALYSIS.md` A). Rollout: additive, cloud first.

## Dependencies on other modules
`pos-sales` (orders and payments carry the shift id), `pricing-tax-tenders` (tender kind `cash` defines cash sales), `pos-provisioning-licensing` (terminal row used as lock), `roles-and-staff` (capabilities).

## Tests
See `docs/features/pos-shifts/TEST_PLAN.md`.

## Risks, gaps and unknowns
See FEATURE.md "Security considerations", "Known limitations", "Unknowns and assumptions".

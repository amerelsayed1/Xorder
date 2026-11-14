# Technical design

Status: as-built for the 2026-10-26 change (XORD-027); plan approved by the owner ("go") with: VAT fix only, existing data untouched, setup-screen line left.
Verified against: xorder-pos `a6f5fe5` (+ uncommitted work), xorder-cloud `06bc8e3` (+ uncommitted work, none in tax files) · Updated 2026-10-26

## Architecture and modules
POS (Flutter, `lib/domain` plain Dart, UI → repository interface → `lib/data/postgres`). The change touches three places only:
1. Repository `saveMoneyConfig` (apps/xorder-pos/lib/data/postgres/postgres_catalog_admin_repository.dart:552): in the existing admin transaction it also runs `SELECT rate_bp FROM pos_tax_groups WHERE restaurant_id=@r AND is_default FOR UPDATE` (:596) and, after the `pos_money_config` upsert, `UPDATE pos_tax_groups SET rate_bp=@vat WHERE restaurant_id=@r AND is_default RETURNING rate_bp` (:626). `vatBp > 10000` is refused first (:581). The audit event gains `default_group_rate_bp` before/after (:646, :652).
2. Pane (apps/xorder-pos/lib/features/admin/presentation/management_taxes_pane.dart): waits for `taxGroupsAllProvider`, seeds the VAT box from the default group (`_defaultRate`, :79; seeding :202-217), and after a successful save invalidates `moneyConfigProvider`, `taxGroupsProvider`, `taxGroupsAllProvider` (:176 region).
3. Cart label (apps/xorder-pos/lib/features/sale/widgets/cart_panel.dart:427-430): from `taxConfig.defaultTaxGroup.rateBp` through `receiptPercent`.

## Source references
apps/xorder-pos/lib/domain/models/ticket.dart:354 (TaxMode), :375 (TaxConfig), :394 (defaultTaxGroup), :771, :783; apps/xorder-pos/lib/domain/models/tax.dart:14 (TaxGroup), :194 (TaxEngine.linesFor); apps/xorder-pos/lib/data/postgres/money_config_codec.dart:21-61; apps/xorder-pos/lib/app/providers.dart:1441, :1468, :1499, :1526; migrations apps/xorder-pos/lib/data/postgres/migrations.dart:1647 (16: groups), :2373 (26: `pos_restaurants.tax_mode`).

## State and data flow
Owner types a rate → `saveMoneyConfig(TaxConfig)` → one transaction: payload upsert + default group UPDATE + audit → pane invalidates providers → `taxConfigProvider` rebuilds → new tickets are priced at the group. Open or parked tickets keep the `TaxConfig` they were started with (apps/xorder-pos/lib/data/postgres/parked_ticket_codec.dart:42-45; UNVERIFIED for live tickets beyond `live_ticket_survives_config_test`, not read).

## Dependencies
`pos_tax_groups` (unique partial index: one default per restaurant, apps/xorder-pos/lib/data/postgres/migrations.dart:1669); `pos_money_config`; Riverpod providers above. The cloud is not involved on offline tills.

## Failure handling and observability
Refusals are `AdminResult` data (`CatalogInvalid`, `NotPermitted`, `AdministratorCredentialRequired`). The UPDATE and the payload upsert commit or roll back together. Audit: `moneyConfigChanged` carries both figures. No logging added.

## Compatibility and rollout
POS-only, no schema or contract change; offline tills only (cloud tills have no editable pane and no default group). Ship with the next POS build; no ordering with the cloud. Rollback: revert the three files; data written is ordinary config. Not shipped, not committed (workspace rules). Follow-ups: XORD-028 (inclusive switch, cloud `tax_mode`); reconciliation of disagreeing tills; setup-screen "VAT 14%" line; the service row label rounds fractions like the VAT label used to.

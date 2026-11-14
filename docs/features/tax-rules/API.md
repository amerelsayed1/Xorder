# API contract

Verified against: xorder-pos `a6f5fe5` (+ uncommitted work), xorder-cloud `06bc8e3` (+ uncommitted work, none in tax files) · Updated 2026-10-26

## Producers and consumers
Producer: cloud `PosBootstrapService` (bundle `money.tax_rules`), contract POS-BE-013, status **READY** (apps/xorder-pos/docs/coordination/BACKEND_TO_POS.md:207). Consumers: POS `BootstrapSeeder` and `MoneyConfigCodec`. The 2026-10-26 change adds **no** endpoint, field or response change.

## Verified endpoints (method/path)
Dashboard (restaurant admin), from apps/xorder-cloud/apps/api/routes/api.php:688-697: `GET tax-rules`; `POST tax-rules`, `PUT tax-rules/{taxRule}`, `DELETE tax-rules/{taxRule}` (the last three under `can:settings.update` + `subscription.writable`). Path prefix of that group: UNVERIFIED (not read). POS bootstrap: `money.tax_rules[]` = `id, name, rate_bp, mode, applies_to, sort_order` (apps/xorder-cloud/apps/api/app/Services/PosBootstrapService.php:118-122).

## Authentication and authorization
Dashboard routes sit inside the tenant-authenticated group (UNVERIFIED which middleware, not traced); writes need `settings.update`. Bootstrap is behind the device credential.

## Request and response examples (redacted)
Create: `{"name": "VAT", "rate_bp": 1400, "mode": "exclusive", "applies_to": null, "sort_order": 0}` (validation: apps/xorder-cloud/apps/api/app/Http/Requests/Dashboard/StoreTaxRuleRequest.php:17-27). Bundle item: `{"id": 1, "name": "VAT", "rate_bp": 1400, "mode": "exclusive", "applies_to": [], "sort_order": 0}`.

## Error formats
Standard Laravel 422 validation errors (not traced further; UNVERIFIED).

## Backward compatibility
**Gap, not fixed (XORD-028):** the till reads a top-level `money.tax_mode` (apps/xorder-pos/lib/data/postgres/money_config_codec.dart:40) that the bundle never sends, so a cloud till is always exclusive whatever a rule's `mode` says; the server's engine honours the rule's mode (apps/xorder-cloud/apps/api/app/Services/PosPricingEngine.php:276). Fix would be an additive bundle key, cloud first (`api-contracts.md`). Also: the till uses only the first rule (codec :28), the server applies all.

## Contract tests
Cloud: `tests/Feature/Pos/PosOrdersTest.php:94` (`test_tax_and_charges_follow_the_configured_rules_in_basis_points`, exclusive 14% on service+food). No test found for an inclusive rule reaching the till, nor for `money.tax_rules` shape (UNVERIFIED, grep limited to `TaxRule` in `tests/`).

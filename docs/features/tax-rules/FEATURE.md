# Feature specification

Status: partially verified — **implemented** for the offline POS VAT rate (this slice, changed 2026-10-26); the cloud rule editor and the cloud pricing engine are **traced only as far as the bootstrap hand-off** and are otherwise UNVERIFIED. Documentation state: `drafted`, partial scope.
Verified against: xorder-pos `a6f5fe5` (+ uncommitted work), xorder-cloud `06bc8e3` (+ uncommitted work, none in tax files) · Updated 2026-10-26

## Summary
How much tax a sale carries. The restaurant has a VAT rate, optionally named rates per product or category (tax groups), and a mode (prices exclusive of tax, or inclusive). On a **cloud till** the platform's tax rules author the rate (POS-BE-013, READY). On an **offline till** the owner sets it in Back Office › Management › Taxes. A ticket is taxed at the product's group, or the restaurant's **default group**, and the service charge is taxed at the default group too (apps/xorder-pos/lib/domain/models/ticket.dart:394, :771).

## Scope and exclusions
In scope (documented here): the offline VAT box and its relation to the default tax group; how a ticket picks its rate; the cart's VAT label; the cloud rule → bundle → till hand-off.
Not documented yet (UNVERIFIED / pending): the cloud dashboard tax-rule screen, `PosPricingEngine` beyond the tax step, ETA filing, tax reports, purchase-order tax. The tax-inclusive **switch** is not built (XORD-028). Venue models: all four need it; zero-rated and non-14% restaurants (cafés, trucks, cloud kitchens) are the ones the 2026-10-26 fix helps. UNVERIFIED: no venue model was traced individually.

## Actors and permissions
- Offline POS: `settings.manage` saves the VAT box (apps/xorder-pos/lib/data/postgres/postgres_catalog_admin_repository.dart:552 and the check just below it); the pane exists only where the till authors its own money rules, a cloud till shows "owned by the platform".
- Cloud dashboard: read `GET tax-rules` for the tenant; write routes need `can:settings.update` and a writable subscription (apps/xorder-cloud/apps/api/routes/api.php:688-697).

## Cloud flow
Owner creates a rule (`name`, `rate_bp` 0–10000, `mode` inclusive|exclusive, optional scope) (apps/xorder-cloud/apps/api/app/Http/Requests/Dashboard/StoreTaxRuleRequest.php:17-27). `PosBootstrapService` sends all rules in `money.tax_rules`, each with its own `mode` (apps/xorder-cloud/apps/api/app/Services/PosBootstrapService.php:118-122). **No top-level `tax_mode` is sent** (grep of `app/`). The server's `PosPricingEngine::tax` sums every matching rule, inclusive ones extracted, exclusive ones added (apps/xorder-cloud/apps/api/app/Services/PosPricingEngine.php:264-290).

## Desktop POS flow
1. Bundle seeded into `pos_money_config` verbatim (apps/xorder-pos/lib/data/cloud/bootstrap_seeder.dart:352-370). `MoneyConfigCodec.toTaxConfig` takes the **first** rule's `rate_bp` as `vatBp` and reads a top-level `tax_mode` (apps/xorder-pos/lib/data/postgres/money_config_codec.dart:21-41). Cloud setup seeds **no** default group (comment apps/xorder-pos/lib/app/providers.dart:2921-2927).
2. Offline setup seeds a default group "VAT" at 1400 bp (apps/xorder-pos/lib/data/postgres/local_bootstrap.dart:545; called at apps/xorder-pos/lib/features/setup/application/setup_controller.dart:790 and apps/xorder-pos/bin/pos_migrate.dart:631); migration 16 does the same for existing restaurants (apps/xorder-pos/lib/data/postgres/migrations.dart:1717).
3. `taxConfigProvider` folds the active groups into `TaxConfig.taxGroups` (apps/xorder-pos/lib/app/providers.dart:1441).
4. `TaxConfig.defaultTaxGroup` returns the stored default group, and builds one from `vatBp` only when there is none (apps/xorder-pos/lib/domain/models/ticket.dart:394).
5. `Ticket.totals` accumulates a base per group, rounds once per rate, taxes service at the default group; inclusive prices extract the tax and do not add it (apps/xorder-pos/lib/domain/models/ticket.dart:771-783, apps/xorder-pos/lib/domain/models/tax.dart:194).
6. Cart shows "VAT x%" from the **default group's** rate (apps/xorder-pos/lib/features/sale/widgets/cart_panel.dart:427-430); the receipt prints each tax line's own rate (apps/xorder-pos/lib/features/receipt/receipt_document.dart:382).

## Business rules
- BR-1 Rates are integer basis points, never floats; rounding is half-up once per rate.
- BR-2 When a default tax group exists, it — not `vatBp` — is the rate a ticket is taxed at for products with no group, and for the service charge.
- BR-3 (changed 2026-10-26) Saving the VAT box on an offline till sets `vat_bp` **and** the default group's rate in one transaction; over 100% is refused (apps/xorder-pos/lib/data/postgres/postgres_catalog_admin_repository.dart:581, :626).
- BR-4 The VAT box displays the default group's rate when one exists, else `vatBp` (apps/xorder-pos/lib/features/admin/presentation/management_taxes_pane.dart:79, :217).
- BR-5 A restaurant is exclusive **or** inclusive, never a mixture (apps/xorder-pos/lib/domain/models/ticket.dart:345-362). Nothing on any screen sets it.
- BR-6 The single group row is never created by saving; no default group → behaves as before.
- BR-7 Nothing stored is rewritten by the change; tills where `vat_bp` and the group already disagree keep charging the group's rate.

## Edge cases and failure handling
- Only the first cloud rule becomes `vatBp`; further rules are ignored by the till although the server applies all (UNVERIFIED end to end; codec :28).
- A till that cannot read its groups falls back to `vatBp` (apps/xorder-pos/lib/app/providers.dart:1468 `on Object` branch).
- Inclusive: the bill's rows do not add up (VAT is contained) and nothing says "included"; the order does not record the mode.
- Static copy on the setup review screen says "VAT 14%" regardless (apps/xorder-pos/lib/features/setup/presentation/setup_panes.dart:1778); not fixed.

## Acceptance criteria
- AC-1 Offline, VAT box saved as 0 with a seeded default group → the next ticket carries no VAT.
- AC-2 Any rate 0–100% saved moves exactly the default group; other groups untouched; no group → still saves.
- AC-3 The box opens at the rate actually charged.
- AC-4 Cart VAT label equals the applied rate (0, 14, 12.5).
- AC-5 Audit event carries the group's rate before and after.
- AC-6 After saving, the running till re-reads the groups.
- AC-7 No migration; no stored value rewritten; tills with no group unchanged.

## Confirmed source references
All `path:line` citations above; test names in TEST_PLAN.md. Investigation: docs/harness/investigations/vat-box-zero-still-charges-14-and-inclusive-option.md.

## Unknowns and assumptions
- UNVERIFIED: that the reporter's till was an offline till (inferred from the editable pane and the `MAIN` order prefix, apps/xorder-pos/lib/features/setup/application/setup_controller.dart:773).
- UNVERIFIED: cloud tills upgraded through migration 16 may hold a 14% group the bundle never overwrites; no real data read.
- UNVERIFIED: whether affected orders were filed to ETA (apps/xorder-pos/lib/domain/services/eta_filing.dart:211 builds from `totals.taxLines`).
- Open decision: reconcile tills whose box and group disagree (not done).
- Open domain question: is service charge tax-inclusive when prices are (XORD-028).
- The cloud dashboard screen and its tests are not traced.

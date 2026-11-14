# vat-box-zero-still-charges-14-and-inclusive-option — VAT set to 0 still charges 14%; tax-inclusive has no switch

Status: investigated · 2026-10-26 · Confidence: **confirmed** (mechanism, reproduced to the piastre) · **likely** (that the reporter's till is an *offline* till — see §9) · Verified against: xorder-pos `a6f5fe5`, xorder-cloud `06bc8e3`. Both repos have uncommitted changes; none touch tax (POS: `management_taxes_pane.dart` and `tax_group_dialog.dart` only gain a `languages:` argument; cloud: `PosBootstrapService.php` adds `bilingual`, `PosMoneyView.vue` is unrelated styling/i18n).

Proposed tracker id (not written to `docs/qa/XORDER_QA_FINDINGS.md`; this skill edits nothing outside this report): **XORD-027** (VAT box ignored) and **XORD-028** (inclusive switch missing / cloud mode not delivered).

## 1. Symptom
Reporter, in their words: "it show taxes as %14 even i make it 0", and "i want to make option to make it inclusive if there taxes".
Evidence: a receipt (order `MAIN-2026-000006`, dine-in table A1, Arabic) showing subtotal 1,050.00, service (12%) 126.00, **VAT (14%) 164.64**, total 1,340.64 EGP.
Expected: after setting VAT to 0 the sale carries no VAT: total 1,176.00. Actual: 14% is still charged and printed.
Second ask: a switch to say "prices already include tax".

## 2. How it was reproduced
Throwaway script (scratchpad, not in any repo), pure Dart against the real `Ticket` / `MoneyConfigCodec`:

```
dart --packages=.dart_tool/package_config.json <scratchpad>/tax_repro.dart     (cwd apps/xorder-pos)
```
Real output (1,050.00 of food, service 12% dine-in):
```
A  offline, VAT box = 0, seeded default group present
   subtotal=105000 service=12600 vat=16464 total=134064 taxLines=[VAT@1400=16464]  cartPanelLabelRate=0.0%
B  offline, VAT box = 0, NO groups
   subtotal=105000 service=12600 vat=0 total=117600 taxLines=[VAT@0=0]  cartPanelLabelRate=0.0%
C  default group edited to 0
   subtotal=105000 service=12600 vat=0 total=117600 taxLines=[VAT@0=0]  cartPanelLabelRate=14.0%
D  cloud inclusive rule -> taxMode=TaxMode.exclusive isInclusive=false
E  cloud rule 0%, no groups
   subtotal=105000 service=0 vat=0 total=105000 taxLines=[VAT@0=0]  cartPanelLabelRate=0.0%
F  cloud two rules (14%, 0%) -> vatBp=1400
G  inclusive 14% + service 12%, no groups
   subtotal=105000 service=12600 vat=14442 total=117600 taxLines=[VAT@1400=14442]  cartPanelLabelRate=14.0%
```
**Case A reproduces the receipt exactly** (126.00 / 164.64 / 1,340.64). No existing test covers it (§7). Not run against PostgreSQL or a running app; the seeding of the group was established by reading code.

## 3. Root cause
**Two stores for "the VAT rate", and the till reads the wrong one.**

1. The Taxes pane's "VAT" box (`management_taxes_pane.dart:140-145`, `_save`) writes `vatBp` into `pos_money_config` via `saveMoneyConfig` (`postgres_catalog_admin_repository.dart:552-625`).
2. But every offline restaurant is also given a **default tax group at 14%**: `LocalBootstrap.seedTaxGroup(... rateBp = 1400)` (`local_bootstrap.dart:545-565`), called by setup (`setup_controller.dart:790`) and `bin/pos_migrate.dart:631`, neither passing a rate; migration 16 (`migrations.dart:1717-1730`) does the same for restaurants that existed, falling back to 1400.
3. `taxConfigProvider` loads those rows into `TaxConfig.taxGroups` (`providers.dart:1441-1462`), and `TaxConfig.defaultTaxGroup` (`ticket.dart:394-407`) **returns the stored `is_default` group and only builds a group from `vatBp` when there is none**. `Ticket.totals` taxes every line *and the service charge* through it (`ticket.dart:771`, `groupFor` → `defaultTaxGroup`). So `vatBp` is never consulted once the seeded group exists.
4. The receipt prints `line.rateBp` of the tax line (`receipt_document.dart:379-386`), so it faithfully says 14%.

**Cause:** the pane edits `vatBp`, which is dead once a default group exists. **Symptom:** 14% charged and printed. **Contributing conditions:**
- The pane's own copy says the single rate is the fallback only "with no groups" (`taxGroupsFallback`), but a fresh till always has one group, so the box looks live and is not. The group list sits below the box; nothing says the group wins.
- `cart_panel.dart:423-426` labels the cart "VAT x%" from `vatBp`, not from the rate actually applied: in case A the cart says **"VAT 0%" next to 164.64**; in case C (group edited to 0) it says **"VAT 14%" next to 0.00**. The cashier cannot tell which number is real.
- `saveMoneyConfig` audits `vat_bp` only, so the audit trail says the VAT was set to 0 on a till that kept charging 14%.
- The cloud-till seeder comment (`providers.dart:2921-2927`) shows the authors knew a seeded 14% group overrides `vatBp`, and protected the *cloud* path only.

## 4. Evidence and alternatives ruled out
- Predicted from the mechanism and confirmed: B (no group) charges 0; C (edit the group) charges 0; only A (box = 0 + seeded group) charges 14.
- Ruled out: engine rounding or `percentBp(0)` (B, C, E all give 0); the codec dropping a 0 rate (`_bp` handles 0; E); the 0 being rejected on save (`saveMoneyConfig` only refuses negatives; `saveTaxGroup` allows 0–10000; `TaxGroupDialog` allows 0–100); receipt formatting (it prints the line's own rate).
- Cloud till at 0%: works (E), because the cloud seeder deliberately seeds no group. Not proven for a cloud install **upgraded** through migration 16, which could have created a 14% group (`COALESCE(..., 1400)`) before any bundle existed. UNVERIFIED, no real data read.
- Case F: on a cloud till only the **first** tax rule (by `sort_order, id`) is used (`money_config_codec.dart:26`); a second rule the owner adds to "make it 0" is silently ignored, and the rest are never applied by the till although the server's `PosPricingEngine::tax` sums them all. Related, separate defect.

## 5. Impact
- **Money / compliance:** customers of any *offline* till whose owner set VAT to 0 (or any rate other than 14) in the box were charged 14%. Those totals are stored in `pos_orders.vat_minor` / `pos_order_taxes`, and the ETA filing is built from `totals.taxLines` (`eta_filing.dart:211`), so wrong VAT is also what would be filed. Number of affected tills/orders: unknown, no real DB read (forbidden).
- Venue models: all four. Cafés and cloud kitchens with zero-rated or exempt items, food trucks with a small flat menu, and any restaurant that was told "VAT 0" at install. Also hits a branch configured at e.g. 15%: the box shows 15 while a 14 group charges.
- Data already wrong: yes, on those tills. Not repairable by a rule; whether past orders are corrected is an owner/accountant decision.
- No tenant or permission exposure.
- Inclusive request (§6b): **cloud tills cannot be inclusive today.** The dashboard form has a per-rule `inclusive/exclusive` mode (`PosMoneyView.vue:145`, `StoreTaxRuleRequest:20`); `PosBootstrapService.php:118-122` sends it per rule, but the till reads a **top-level `tax_mode`** (`money_config_codec.dart:37`) which the cloud never sends (`grep tax_mode` in `apps/api/app` returns nothing). Case D: an inclusive dashboard rule becomes exclusive on the till, so the till adds 14% on top while the server's engine (`PosPricingEngine.php:276-279`) treats it as contained, a till-vs-server total disagreement (`totals_mismatch`, per `PosOrderService.php:216-291`; mismatch path not run).
- Offline tills can be inclusive in the engine and DB (`tax_mode`, migration 26; `tax_mode_test.dart`), but **no screen sets it** (`management_taxes_pane.dart:51-57` says so; `grep taxMode lib/features lib/app` finds nothing else).

## 6. Fix options
### 6a. VAT 0 still charged (narrowest first)
1. **Make the box and the default group one thing (recommended).** In the offline Taxes pane the VAT box reads and writes the *default group's* rate (`saveTaxGroup` on the default row, plus `vatBp` kept in step in the same transaction), and shows which group it is editing. `defaultTaxGroup` stays the single source for the engine. Cart label and receipt derive the percentage from the group/tax lines, not `vatBp`. Trade-off: touches one pane, one repository method and one label; no schema change; groups keep working.
2. Make `vatBp` win (change `defaultTaxGroup` to use `vatBp`). One line, but it breaks the documented "a stored default group beats vatBp" rule, the per-group design and `tax_groups_wiring_test`, and silently changes what *existing* tills charge. Not recommended.
3. Hide the box whenever any group exists and point to the group list. Smallest UI change, but a cashier-visible "VAT %" label would still need fixing, and the box was the thing the reporter used.
- **Must not change:** what a till already charges until the owner edits it (no migration that rewrites `rate_bp`); basis-point integers; round-once-per-rate; the cloud seeder's "no default group" rule; wire shapes. Which value wins for tills where the box and the group already disagree (box says 15, group says 14, customers pay 14) is an **owner decision**; default is to leave data alone and show the effective rate.
- Fix the cart label (`cart_panel.dart:423-426`) and the audit entry (`saveMoneyConfig`) in the same change, since they hide this exact class of bug.
- Cloud (separate, smaller): decide whether the till should apply all tax rules (as the server does) or the dashboard should refuse a second unscoped rule. Report-only here.

### 6b. "Make it inclusive"
This is a feature on top of a working engine, so `/develop-feature` should specify it; the investigation facts it needs:
- **Offline:** add a switch to the Taxes pane bound to the already-carried `_taxMode` (`management_taxes_pane.dart:57`); engine, codec, parked tickets (`parked_ticket_codec.dart:45`) and reports (`postgres_reports_repository.dart:424-535`) already understand it. Needs copy in both languages, and a decision on what happens to open/parked tickets when the mode flips (they keep their own config today).
- **Cloud:** either the bundle emits a restaurant-level `tax_mode` (additive key; older tills ignore it, so ship cloud first), or the dashboard gets one restaurant-level switch instead of a per-rule mode. The till is deliberately "one or the other, not a mixture" (`ticket.dart:345-355`), so mixed per-rule modes need a defined result (refuse in the dashboard is the narrowest).
- **Open domain question:** in inclusive mode the engine adds the service charge on top, then extracts VAT *from net + service* (case G: VAT 144.42 on 1,176.00). Whether the service charge is itself VAT-inclusive, and what an inclusive Egyptian receipt should show, must be confirmed by the owner/accountant before this ships.

## 7. Tests the fix needs
- Regression that would have caught it, in `test/features/tax_groups_wiring_test.dart` (or a new `tax_vat_box_test.dart`): real `taxConfigProvider` with a stored `TaxConfig(vatBp: 0)` **and** a default group, assert `totals.vat == 0`. Today every wiring test uses `vatBp: 1400` with a 1400 group, so the two stores never disagreed. Add: pane widget test that types `0`, taps `rates-save` and asserts the *ticket's* VAT, not just the saved config (`money_panes_ownership_test.dart:187-217` asserts only `catalogue.saved?.vatBp`, which is why it passed).
- PostgreSQL test (`test/data/postgres_integration_test.dart`, `POS_PG_HOST` required): saving the rate leaves one default group at that rate.
- Cart label test (`cart_totals_alignment_test.dart`): label equals the applied rate in both the A and C situations.
- Codec/bundle: `MoneyConfigCodec` reads a top-level `tax_mode`; cloud feature test that the bundle carries it; a `PosPricingEngine` test pair for inclusive/exclusive.
- Run: `flutter analyze`, `tax_lines_test`, `tax_mode_test`, `tax_groups_wiring_test`, `ticket_totals_golden_test`, `receipt_document_test`, `cart_totals_alignment_test`, `money_panes_ownership_test`; cloud `php artisan test --filter Pos` (SQLite, cannot show PostgreSQL behavior).

## 8. Approvals the fix needs
- Money-calculation behavior change (the effective VAT rate on offline tills moves for owners who edit it): ask approval before implementing.
- Inclusive on cloud: **contract change** (additive bundle key) → a `POS-BE-xxx` row in the coordination ledger, cloud deployed first. Anything reaching `xorder-cloud` `main` is a production deploy and needs `/release-check` and the owner's own push.
- No migration is required by the narrowest option. Any data reconciliation of existing tills is separate and needs explicit approval.
- Money-integrity finding: also route to `/security-audit`.

## 9. Open questions and what could not be verified
- **Which deployment mode the reporter's till is.** The pane is editable only offline (cloud shows a "platform owns this" notice), and the order prefix `MAIN` is what offline setup hard-codes (`setup_controller.dart:772`), so offline is likely, not proven. If it is a cloud till, the cause is different and unproven (candidates: a migration-16 group on an upgraded install, or a second dashboard rule). Reading the till's `pos_tax_groups` and `pos_money_config` rows would settle it; not done (real DB).
- How many tills/orders are affected; whether any 0%-VAT orders were filed to ETA.
- Whether the service charge should be taxed at all when prices are inclusive.
- Whether service and VAT being applied in dine-in only (`serviceDineInOnly`) is intended for the reporter's venue.
- Not run: a running app, PostgreSQL-backed tests, the cloud test suite.

# XOrder — QA Findings & Implementation Backlog

**Reported by:** Amer · **Last updated:** 2026-10-25 (status review) · **Scope:** POS, Back Office, Admin, licences, staff, menu, tables, localization
**Status:** 33 findings (XORD-033 added 2026-10-26, the open-day notice moves to the status bar); (XORD-032 added 2026-10-26, section actions on the Sections page); (XORD-031 added 2026-10-26, table seats optional); (XORD-030 added 2026-10-26, the cashier's top bar); (XORD-029 added 2026-10-26, POS PostgreSQL suite fails at HEAD); (XORD-024 to 026 added 2026-10-26, described in `docs/features/receipt-logo-and-layout/FEATURE.md`; XORD-027 and 028 added 2026-10-26, `docs/harness/investigations/vat-box-zero-still-charges-14-and-inclusive-option.md`). **6 verified** (003, 004, 010, 017, 019, 020) · **16 implemented, awaiting QA** (001, 002, 005, 006, 007, 009, 016, 018, 021, 024, 025, 026, 027, 031, 032, 033) · **1 plan written** (011) · **2 investigated** (014, 022) · **6 not started** (008, 012, 013, 015, 023, 028). Nothing is committed or pushed. Evidence: section 8.
**Source of truth:** this file (`docs/qa/`); copies in Downloads are superseded. It records user-observed problems and requested changes, and from section 8 what engineering has done about each.
**Tick rule:** `[x]` = implemented **and** verified by an automated check that was actually run; the tick says which. Never tick because code changed. A master line is ticked only when every criterion under it is ticked or explicitly caveated. Implemented-but-unticked items are explained in section 8.

**Contents:** 1 Instructions · 2 Findings (001–023) · 3 Shared requirements · 4 Verification matrix · 5 Open questions · 6 Output format · 7 New findings · 8 Status review

## 1. Instructions for Claude

1. Read this entire document, then inspect the actual XOrder repository and its existing architecture, project instructions, tests and coding conventions.
2. Locate the correct implementation across the Flutter POS/desktop client, Vue Admin/Back Office, Laravel APIs and PostgreSQL persistence **as applicable**. Do not assume every finding touches every stack layer.
3. For each item, first reproduce or verify the current behavior and document the relevant files. Distinguish a missing feature from a regression.
4. Propose a short implementation plan with dependencies, migration impact, affected permissions, feature/plan eligibility and tests. Resolve the **Open questions** below before making product decisions that alter behavior.
5. Reuse existing components, validation, localization, authorization and domain services. Avoid duplicate implementations across screens; preserve backwards compatibility and offline behavior.
6. Implement in small, reviewable changes, ideally one ticket per change or a coherent dependency group. Do not silently alter unrelated UI or schema.
7. Include unit, widget/component, API authorization and integration/regression tests where meaningful. Run relevant formatting, static analysis, tests and builds; report any checks that were unavailable.
8. Report per-ticket completion status with modified files, behavior, tests, migration notes, screenshots where useful, and outstanding questions. Do not claim a ticket resolved without verification.

### Findings tracker

Priorities are **proposed triage priorities**, subject to product confirmation (P1 = high/security or broken flow; P2 = standard feature; P3 = small polish). "Bug" = observed failure; "Enhancement" = requested change; "Localization" = text correction. **Done** is the master checkbox (see the tick rule above).

| Done | ID | Title | Classification | Pri | Module | Status (2026-10-25) |
|---|---|---|---|---|---|---|
| [ ] | XORD-001 | Select/create a customer during a POS order | Enhancement | P2 | POS / Orders | Implemented, partial: the order's customer is not yet sent to the cloud |
| [ ] | XORD-002 | Configurable, plan-eligible POS order types; at least one required | Enhancement | P2 | POS Home / Plans | Implemented, partial: per branch, no POS Home buttons, no order-time check |
| [x] | XORD-003 | Arabic text: غير متصل → لوكال (Local licence label) | Localization | P3 | Admin / POS Licences | **Verified** |
| [x] | XORD-004 | Normalize Arabic numerals in phone/price inputs | Enhancement | P2 | Shared Forms | **Verified** (caveats in section 8) |
| [ ] | XORD-005 | Show translatable fields only for enabled content languages | Enhancement | P2 | Shared Forms / Settings | Implemented: cloud complete; POS category, item, combo, extras/size groups and seven further dialogs; widget-tested, not seen in a running app; refresh criterion untested |
| [ ] | XORD-006 | Bulk-create tables | Enhancement | P2 | Table Management | Implemented in cloud and POS Back Office; POS tested, cloud generator UI untested |
| [ ] | XORD-007 | Bulk-create menu categories | Enhancement | P2 | Menu Management | Implemented in cloud Back Office; UI untested; POS Back Office not built |
| [ ] | XORD-008 | Permission-controlled Back Office top-menu entry | Security / Enhancement | P1 | POS Navigation / RBAC | Not started |
| [ ] | XORD-009 | Edit/update an existing licence | Enhancement | P2 | Licence Management | Implemented through renewal; UI untested |
| [x] | XORD-010 | Staff Management gesture throws Flutter TypeError | Confirmed runtime bug | P1 | Flutter Staff Management | **Verified** |
| [ ] | XORD-011 | Business owners create their own roles | Enhancement / Security | P1 | Staff / RBAC | Plan written, awaiting decisions |
| [ ] | XORD-012 | Deleted menu items remain visible (make deletion permanent) | Observed functional bug | P1 | Menu / POS / Sync | Not started; cloud findings recorded |
| [ ] | XORD-013 | Physically delete a category and its exclusive products | Business rule / Data integrity | P1 | Menu / Databases | Not started |
| [ ] | XORD-014 | Verify and enforce the product–category relationship in both databases | Data integrity investigation | P1 | Databases / Sync | Investigated: the reported missing relationship was not found |
| [ ] | XORD-015 | Link payment methods to financial accounts | Financial integrity / Enhancement | P1 | Finance / Payments | **Stage 1 implemented 2026-10-26** (accounts + default per method/branch); stage 2 (payments, override, transfers) not started |
| [ ] | XORD-016 | Local licence page shows which devices used the key | Enhancement | P2 | Licence Management | Implemented; UI untested |
| [x] | XORD-017 | Refuse a new device once a local licence's seats are all in use | Security / Enhancement | P1 | Licence Management / Activation | **Verified** (caveats in section 8) |
| [ ] | XORD-018 | Licence page "Client" card values misaligned in Arabic | UI bug | P3 | Licence Management | Implemented; visual check pending |
| [x] | XORD-019 | POS Orders screen misaligned in Arabic | UI bug | P2 | POS Back Office / Orders | **Verified** |
| [x] | XORD-020 | POS Orders search box is a thin strip beside the filter chips | UI bug | P3 | POS Back Office / Orders | **Verified** |
| [ ] | XORD-021 | Business logo: offline management, cloud storage, sync, POS display | Enhancement | P2 | Branding / Back Office / Sync | Implemented; tests pass, UI not seen in a running app |
| [ ] | XORD-022 | Back Office navigation restructuring and UX (epic, A–F) | Epic / UI-UX, Security | P1 | POS Back Office / Navigation / RBAC | Stages 1–3 implemented 2026-10-25 (A–D partly); E and F not started; nine decisions pending |
| [ ] | 022-A | Remove duplicate navigation entries | UI-UX | High | | Payments merged, labels renamed; Sales/order-history entries wait on your decision |
| [ ] | 022-B | Reorganize the menu hierarchy | UI-UX | High | | Implemented and tested (two criteria ticked); the rest of the map waits on your decisions |
| [ ] | 022-C | Consistent labels and terminology (Arabic and English) | Localization | Medium | | Main labels renamed in both languages; Arabic wording needs your read |
| [ ] | 022-D | Separate Settings from user-account actions | UI-UX | High | | Account menu built and tested (two criteria ticked); toggles and keyboard not done |
| [ ] | 022-E | Consistent dropdown design and keyboard behaviour | UI-UX | Medium | | Not looked at in a running app |
| [ ] | 022-F | Permission-based navigation visibility | Security | High | | Mostly built already; 21 panes ungated, pane gates need your approval |
| [ ] | XORD-023 | Keep the dashboard interface language separate from the content language | Bug / design | P2 | Cloud dashboard / Settings | Not started; found while closing XORD-005 |
| [ ] | XORD-024 | Print the business logo on the receipt (header, switchable; XOrder only in the footer) | Enhancement | P2 | POS Receipt / Printing | Implemented 2026-10-26 (`docs/features/receipt-logo-and-layout/`); tests pass, not seen on a real printer |
| [ ] | XORD-025 | Receipt amounts do not line up on the decimal in Arabic; currency label under the total is centred | UI bug | P3 | POS Receipt | Implemented 2026-10-26; measured on the printed bitmap and the preview, not seen on paper |
| [ ] | XORD-026 | Receipt shows the currency only on the total; show it beside every amount | Bug / Enhancement | P2 | POS Receipt | Implemented 2026-10-26; reverses a deliberate choice of 2026-10-25 |
| [ ] | XORD-027 | VAT set to 0 in Management › Taxes still charged and printed at 14% | Confirmed bug (money) | P1 | POS Back Office / Tax | Implemented 2026-10-26 (offline tills); tests pass, not seen in a running app; tills where the box and the group already disagree are not repaired |
| [ ] | XORD-028 | "Prices include tax" switch (tax-inclusive pricing) on the till and for cloud tills | Enhancement | P2 | POS Back Office / Tax / Cloud bundle | Not started; needs `/develop-feature` (bill wording, order record, cloud `tax_mode`) |
| [ ] | XORD-029 | The POS PostgreSQL test suite (`scripts/check.sh`) fails at the committed revision on a fresh database | Test infrastructure (pre-existing) | P2 | POS tests | Found 2026-10-26 while testing XORD-015; **not investigated** |
| [ ] | XORD-030 | The window's top bar (Settings and the user-name menu) shows for a cashier | UI / permissions | P2 | POS shell | Implemented 2026-10-26 (owner decision); tests pass, not seen in a running app |
| [ ] | XORD-033 | The "business day is still open" notice belongs in the bottom status bar, not a banner on the start screen | UI | P3 | POS shell / Start | Implemented 2026-10-26; tests pass, not seen in a running app |
| [ ] | XORD-032 | Each section on the Sections/Menu page has three actions: an on/off switch, Edit, Delete | UI / Enhancement | P2 | POS Back Office / Menu | Implemented 2026-10-26; **no migration**; tests pass, not seen in a running app |
| [ ] | XORD-031 | A table's Seats box must not be required (Add several tables, and the single-table form); editing an existing table failed | Enhancement + bug found | P2 | POS Back Office / Floor / local DB | Implemented 2026-10-26 (owner chose truly optional); **migration 61 written, not applied to any real database**; tests pass, not seen in a running app |
| [ ] | XORD-034 | Refund button shown to a cashier who cannot refund alone | UI / permissions | P2 | POS Orders / Sales | Investigated 2026-10-27, not fixed: the button is drawn because refund is lendable (supervisor PIN follows); owner decision needed (hide or keep) |
| [ ] | XORD-035 | One name box on every POS form, in the till's language | Enhancement | P2 | POS menu / settings forms | Implemented (committed `c67c754`); widget and PostgreSQL-seed tested; wizard call and running app not checked |
| [ ] | XORD-036 | Order number shared by every till, restarting each trading day (invoice number unchanged) | Enhancement | P2 | POS Orders / Receipt / History | Implemented 2026-10-28, uncommitted; **migration 63 written, not applied to any real database**; PostgreSQL and widget tests pass; not seen on a till or on paper; cloud-mode multi-till branches not covered (decision) |
| [ ] | XORD-037 | Physical keyboard digits do not enter the PIN after a key is tapped (lock screen, sign-in and shift dialogs) | POS bug | P1 | POS Lock / Shift | Fixed 2026-10-28, uncommitted (branch `fix/pos-pin-keyboard`); widget tests pass and the fix is mutation-checked; not tried on a real Windows/macOS keyboard |
| [ ] | XORD-038 | Identical items from later rounds print as separate receipt lines | POS bug | P2 | POS Receipt | Fixed 2026-10-29, uncommitted (branch `fix/receipt-merge-rounds`); unit and widget tests pass and are mutation-checked; paper not seen |
| [ ] | XORD-039 | `excel_export_test` "Sales the owner's file holds every page…" fails when the date changes (file name `sales-<today>-<yesterday>.xlsx`) | Test (date-dependent), pre-existing | P3 | POS tests / Excel export | Found 2026-10-29: fails identically on untouched `main`; **not investigated** |
| [ ] | XORD-040 | Dark-mode shortcut removed from the POS Settings menu (theme stays in Settings › Appearance) | UI / UX | P3 | POS Navigation | Done 2026-10-29, uncommitted (branch `fix/settings-no-theme-toggle`); widget tests pass and are mutation-checked; menu not seen on screen |
| [ ] | XORD-041 | Dropdowns consistent: form dropdowns match text fields, one filter dropdown (POS; web `<select>` not started) | UI / UX | P2 | POS Back Office / History | POS done 2026-10-29, uncommitted (branch `fix/dropdown-consistency`); measured by tests, not seen on screen; web step waits |
| [ ] | XORD-042 | Back Office offers Delete for a revoked POS device that has sales history; the refusal is titled "Something went wrong" | UI / UX | P3 | Back Office › Settings › POS devices (and Super Admin tenant page) | Fixed 2026-11-03, uncommitted (xorder-cloud branch `feat/finance-accounts-and-platform-updates-2026-10-26`); API tests pass and are mutation-checked; web builds; pages not seen; review found no blockers; **index on `orders.pos_terminal_id` needs an owner decision** |
| [ ] | XORD-043 | Terminal delete can remove a shift's cash movements when the shift had no float, close or count | Bug (money record), found in review | P2 | Cloud POS terminals / shifts | Logged 2026-11-03; **not investigated**; owner decision needed |

---

## 2. Detailed Findings

### XORD-001 — Add/select customer while creating a POS order

**Problem:** Cashier needs the ability to add a customer during order creation instead of leaving the sale workflow.

**Expected behavior**

- From the active order, offer a customer selector/search and a **Create Customer** action.
- Search existing customers by supported identifiers (e.g. name or mobile) and link a selected record to the current order.
- Create a customer in a modal/side panel, validate required information, then select the newly created customer automatically.
- Preserve cart lines, modifiers, discounts, quantities, order type and unsaved order state while opening/closing customer UI.
- Permit an order without a customer if existing business rules allow walk-in customers. Do not make it mandatory without product approval.
- Prevent accidental duplicates as supported by the existing customer model; correctly handle offline creation/sync if the POS supports offline sales.
- Any user allowed to create an order may select an existing customer; quick-create additionally requires an assigned permission such as `customers.create`. Role grants are created by the owner under XORD-011.

**Acceptance / QA**

- [x] Customer can be searched and selected without leaving the active order. — *widget test `order_customer_picker_test`: opened from the cart on the sale screen*
- [x] Newly created customer is attached to the same order. — *widget test: created in the dialog, then attached; permission checked as the signed-in person*
- [x] Closing/cancelling the dialog does not clear cart state. — *widget tests: cancel and select both leave lines, order type and totals unchanged*
- [ ] Invalid fields and duplicate handling follow existing rules. — *duplicate phone selects the person already on file, tested; the required-field rule is unchanged and was not re-tested*
- [ ] Works under appropriate cashier permissions and online/offline configurations. — *permissions tested at screen and repository (`pos.operate` to choose, `customers.create` to add); the order's customer is NOT yet sent to the cloud with the order*

**Investigate:** Existing customer entities, order ownership, quick-create forms, local IDs and offline reconciliation.

### XORD-002 — Three order-type actions on POS home, according to plan

**Updated business decision:** Four order types reportedly exist in code. Back Office must allow the business to choose which plan-eligible types appear on POS Home. The original fixed-three requirement has been **superseded** by user configuration.

**Expected behavior**

- Show only order types enabled under **Back Office → Settings → POS Configuration → Order Types**, subject to subscription entitlements.
- Show from **one up to the plan-eligible count**; zero is invalid. Disable attempts to turn off the last enabled type and reject zero-enabled submissions on the backend.
- Hide disabled and unavailable types completely on POS Home; keep configuration visible to authorized managers with clear plan eligibility.
- Owner may change configuration; delegated users require a permission such as `pos.settings.order_types.manage`.
- Store the choice per business, synchronize to tills, and retain last valid offline configuration until sync. Configuration changes must not corrupt open orders.
- Selecting an available type opens its correct order creation/fulfilment flow and initializes that type reliably.
- Enforce the entitlement in business logic/backend as applicable; merely hiding a button must not unlock a restricted order type through another route.
- When licence/plan changes, refresh eligibility safely and preserve in-progress sales.

**Remaining question:** Confirm exact order-type identifiers from code and how plan changes with zero remaining eligible types are resolved. The UI must explain and prevent invalid configurations.

**Acceptance / QA**

- [ ] Eligible types appear exactly once, with correct Arabic/English labels. — *the sale-screen switch lists the branch's offered types; no POS Home buttons were built*
- [ ] At least one eligible order type is enabled at all times; zero is rejected by both UI and backend. — *backend verified (cloud 422 and POS repository refusal, both tested); the cloud checkbox that blocks unticking the last one is not browser-tested*
- [ ] Owner can enable/disable eligible types in Back Office; POS updates after configuration sync. — *cloud change bumps the till config version (tested); the POS pane works for offline installs (tested); the POS refresh on a cloud till was not exercised end to end*
- [ ] Selecting each opens the appropriate workflow. — *existing behaviour, not re-tested*
- [ ] A restricted type cannot be used through direct navigation or API bypass. — *NOT enforced at order time, by decision: a tenant with unset feature flags would be refused sales. Enforced when the list is saved*
- [ ] Plan change and temporary offline entitlement behavior follow approved licence policy. — *licence rule implemented (a licence naming no order types restricts nothing); policy not yet approved*

### XORD-003 — Correct Arabic licence translation

**Reported page:** `http://admin.localhost:8080/pos/licences/new` (developer-local URL; not a public endpoint).

**Confirmed clarification:** Replace the Arabic label **غير متصل** with **لوكال** only for the Local licence/deployment option. Do **not** replace the four sentences describing an "offline customer" or other genuine connectivity states.

**Acceptance / QA**

- [x] The target option on new-licence page displays **لوكال** in Arabic. — *runtime catalogue read: `licence.kind.offline` = لوكال; the rendered page was not viewed*
- [x] English text is unchanged. — *runtime catalogue read: still "Offline"*
- [x] The same semantic option is consistent in related licence edit/detail views, if any. — *list filter, details badge and chooser all use the same key; the operating-mode checkbox (`licence.mode.offline`) is deliberately unchanged*
- [x] Translation is sourced from the localization system, not duplicated as a hardcoded component string. — *all five changes are catalogue strings*

**Investigate:** Exact key and meaning (local deployment/licence vs connectivity status).

### XORD-004 — Convert Arabic digits in mobile and price inputs

**Scope:** All relevant mobile/telephone number and price/amount entry fields throughout POS and administration (including pasted text).

**Normalization:** Arabic-Indic `٠١٢٣٤٥٦٧٨٩` → ASCII `0123456789`; also consider Eastern Arabic/Persian `۰۱۲۳۴۵۶۷۸۹` if supported by the app's audiences. Support mixed-script input.

| Input | Expected normalized value |
|---|---|
| `٠١٠١٢٣٤٥٦٧٨` | `01012345678` |
| `١٢٥٠` | `1250` |
| `١٢٥.٥٠` | `125.50` |
| `١٢3٤٥` | `12345` |

**Implementation guardrails**

- Normalize while typing/pasting without jumping the caret or corrupting selection/composition; normalize again at form boundary/backend where appropriate.
- **Store phone numbers as strings**, preserving leading zeros and optional supported international prefixes. Never parse them as integers.
- Prices need a locale-aware policy for decimal marks (`.` and potentially `٫`) and thousands separators (`٬`, `,`); do not silently reinterpret an ambiguous number or lose precision. Use the project's monetary decimal/minor-unit representation, not floating-point rounding.
- Keep display formatting/localization independent from the canonical submitted numeric representation.
- Validate negatives, decimal scale, maximum amount and empty values according to each field's own rules.

**Acceptance / QA**

- [x] Typing and paste both normalize Arabic and mixed digits. — *POS formatter tests (typing and pasted mixed script); cloud requests fold digits before validation (tested)*
- [x] Leading zeros in telephone numbers remain intact. — *`foldDigits` and `Digits::latin` work on characters, tested with `٠١٠١٢٣٤٥٦٧٨` and `+٢٠…`*
- [x] Prices preserve the intended decimal value and currency precision. — *`Money.tryParse` and the API price rules tested, including `٫` and a refused `٬` thousands mark*
- [x] Editing mid-string, selecting/replacing text and IME composition remain stable. — *formatter keeps length, selection and composing range (tested)*
- [x] Existing validation and stored/submitted values are correct. — *full cloud and POS suites pass*
- [x] Shared reusable mechanism is used where suitable, with tests. — *POS `foldDigits` + `FoldDigitsFormatter`; cloud `Digits` + `NormalizesNumericInput`*

### XORD-005 — Only show fields for enabled content languages

**Business rule:** This refers to **languages enabled in business configuration**, not merely the current interface language (confirmation was requested previously; treat this as the working assumption).

**Configuration decision:** The business owner may change supported content languages. Delegated managers need a permission such as `settings.languages.manage`. Preserve translated data when switching configurations.

| Business content languages | Show in create/edit forms |
|---|---|
| Arabic only | Arabic input only |
| English only | English input only |
| Arabic + English | Both corresponding inputs |

**Expected behavior**

- Apply to translatable entity forms, including menu/categories and other relevant forms that currently expose paired name/description fields.
- Require/validate only the enabled language fields, respecting existing domain constraints.
- When a language is disabled, **do not delete existing stored translations**; hiding a field must not overwrite it with null/empty data on save.
- When re-enabled, the original translation should become available again.
- Keep the interface language separate from content-language availability; RTL layout remains correct.

**Acceptance / QA**

- [x] All three configuration combinations render correct fields. — *POS category, item, combo, extras/size groups, tax group, service charge, payment method, order type, unit, stock item and supplier dialogs tested in all three (`content_languages_dialogs_test` 61, `combos_ui_test`); cloud rules tested in all three. Not seen in a running app; cloud forms not browser-tested; POS stock-adjacent and other non-name screens not checked*
- [x] Create and edit use identical language-visibility rules. — *the same `ContentLanguages::checkName` serves store and update requests (tested both)*
- [x] Disabled-language fields do not block submit. — *API test (blank hidden language on update) and POS widget tests*
- [x] Editing an Arabic-only item does not erase pre-existing English translation. — *API tests fail without the guard (the translation is wiped) and pass with it; POS tests for both single-language modes*
- [ ] Forms loaded before a settings change handle configuration refresh safely. — *session is refreshed after the profile save; not tested*

### XORD-006 — Create multiple tables in one operation

**Expected behavior**

- Preserve the existing single-table create path.
- Add bulk mode with **start number/name prefix**, **quantity**, and supported shared settings (e.g. floor/area and capacity if the domain has them).
- Preview generated sequential names such as `Table 1` through `Table 10` before save.
- Detect duplicates against existing tables and within the generated set, using the relevant branch/area uniqueness rules.
- Use a bounded maximum quantity and atomic or clearly explained partial-failure behavior.
- Respect permissions, licence limits, local storage/offline sync and audit requirements.
- Proposed default naming: `Table 1`, `Table 2`, etc.; proposed batch limit **100**. Confirm this is compatible with existing branch/table number constraints.
- Manage it in Back Office (including when Back Office is opened from POS), not in the regular cashier order-entry flow.

**Acceptance / QA**

- [x] Creating 10 from start 1 produces exactly 10 uniquely numbered tables. — *POS: planner and database tests give `Table 1`…`Table 10`; cloud: the generator fills the same names and the existing endpoint saves them (generator UI untested)*
- [x] Conflicts/invalid quantity are identified before submission. — *POS: the dialog shows the run and names clashing tables, and Add stays off for a quantity outside 1–100, a bad first number or no seats (widget tests); the database check refuses the same again. Cloud: generator warns, untested*
- [x] Repeated clicks/retries do not create duplicate records. — *POS: a second press while the first is in flight sends one batch (widget test); repeating a finished batch is refused as a duplicate (PostgreSQL test). Cloud: API test; the double-click guard is UI, untested*
- [x] Common settings apply correctly; current single-create form still works. — *POS: seats and area apply to every table; the single "Add table" form is unchanged (widget test)*
- [x] Batch failure semantics are tested and user receives a useful outcome. — *all or nothing on both sides; POS names up to five clashing tables, including ones that are out of service, and the dialog stays open with what was typed*
- Decisions: default name `Table N`, limit 100 per batch (a first number from 1 and a last up to 9999); the same unique key `(branch, label)` the single form uses. Audit: one `table.created` row per table, each naming the batch size. Offline installs only, behind `settings.manage`, in Back Office (Settings › Floor); a cloud till's floor stays the platform's. The POS has no table limit in its licence, so none is checked there.

### XORD-007 — Create multiple menu categories in one operation

**Expected behavior**

- Add **Add Another Category** rows to the category creation UI; each row has its own name field(s) for enabled languages (XORD-005).
- Allow removing a pending row without affecting other rows.
- Validate each row, flag duplicate category names against existing data and duplicate names within the batch according to current uniqueness scope.
- Commit categories in one user action with clear success/failure feedback; keep entered values if validation fails.
- Respect menu/branch context, sort order, permission, API constraints and offline support (where applicable).
- Business decision: batch save is **all-or-nothing**; expose bulk creation in Back Office, not as a separate cashier workflow.

**Acceptance / QA**

- [ ] User can add, modify, remove and submit multiple distinct category rows. — *Vue dialog built; no UI test*
- [x] Single-category creation remains available. — *existing single-create tests pass; the dialog keeps the single form*
- [ ] Arabic-only, English-only and bilingual configurations render the expected fields. — *the batch API judges each row by the content languages (tested in all three); the rows' fields are not browser-tested*
- [x] Duplicate and invalid rows are identifiable; no accidental duplicates after retry. — *API tests: errors are keyed by row (`categories.N.name_xx`), duplicates against the menu and within the batch refused, nothing stored*
- [x] Batch persistence follows documented atomic/partial-failure behavior. — *all-or-nothing, including a forced failure on the third row that rolls everything back*

### XORD-008 — Show Back Office in the top app menu only to authorized users

**Location clarification:** The user explicitly means a **Back Office** option in the **top horizontal application navigation bar**, like the supplied screenshot of the Arabic POS/management UI. This is **not** a standalone launcher, bottom navigation item or merely a link buried inside Settings.

**Expected behavior**

- Business owner has Back Office access by default.
- Employees/users with an explicit permission can see and open the Back Office menu item.
- Users without permission do **not** see it at all; do not merely disable it.
- The destination itself and its APIs remain guarded against deep-link/direct URL access.
- Reuse existing RBAC policy or introduce an appropriately scoped permission such as `backoffice.access` if no equivalent exists.
- Resolve company/tenant context and permission updates; avoid granting cross-tenant access.
- Keep consistent top-menu placement and RTL/LTR behavior without disturbing current navigation groups.
- Also expose a Back Office action on authenticated Home for authorized users; **never show it on the lock screen**. An already authenticated/authorized session need not enter a redundant second PIN for navigation; sensitive operations may require reauthentication according to security policy.

**Acceptance / QA**

- [ ] Owner sees the Back Office option in the top bar.
- [ ] Authorized non-owner sees it and can navigate.
- [ ] Unauthorized user does not see it and receives access denial on direct navigation/API use.
- [ ] Permission changes take effect on the defined refresh/session policy.
- [ ] No privilege escalation between tenants, branches or roles.

**Reference:** Screenshot shared in conversation (2026-10-25, Arabic navigation bar). It shows top navigation categories such as الرئيسية، المبيعات، التقارير، المنيو، المخزون، المشتريات، المالية، الأفراد، النظام، الإعدادات. Use the repository's actual nav component; the image clarifies **placement** and layout, not the exact naming of a new route.

### XORD-009 — Add edit/update option for existing licences

**Problem:** Licence management has creation but the user reports that an option to update an existing licence is missing.

**Expected behavior**

- Authorized admin can open an existing licence and choose **Edit / Update Licence**.
- Prefill editable fields from the saved licence; validate and persist allowed updates with clear success/error feedback.
- Differentiate ordinary metadata edits from security-sensitive changes (plan, expiry, activation, device binding, deployment type) and enforce existing business rules/server permissions.
- Preserve immutable licence identifiers and activation metadata unless a separately authorized workflow explicitly changes them.
- Audit who changed what and when. Define propagation/revalidation policy for online and offline terminals.
- Divide the interface into **ordinary metadata editing** (e.g. notes/contact information) and **signed licence revision** (plan, expiry, seats/limits, licensed features). A signed-field edit must issue a correctly re-signed licence, not mutate signed payload bytes in place.

**Acceptance / QA**

- [ ] Edit action is discoverable in licence list/detail UI. — *the edit path is the Renew button on the details page (not on the list); UI not browser-tested*
- [ ] Existing values load correctly; authorized changes persist and display. — *persistence and signed claims tested; the prefilled form is UI, untested*
- [x] Unauthorized requests fail in UI and backend. — *backend: a restaurant owner gets 403 and nothing changes (tested)*
- [x] Device activation/binding is not reset unintentionally. — *fingerprints kept unless changed, the key's device history and the first-activation date carry over a renewal; a rotated key starts clean (all tested)*
- [ ] Changes are audited and safely delivered to entitled terminals. — *audited with before/after (tested); delivery is by the till re-fetching under the same key, not an automatic push*
- [x] Invalid or conflicting updates leave existing licence intact. — *refusals (bad plan, no mode, revoked or already replaced) write nothing; the old row is never edited (tested)*

**Remaining decision:** Confirm full editable field allowlist, who may issue a signed revision, and propagation/device-binding implications.

### XORD-010 — Staff Management tap throws Flutter `_TypeError`

**Classification:** Observed runtime bug. **Observed exception:** `Null check operator used on a null value` during an `onTap` gesture in Staff Management. The entire widget/app impact needs reproduction.

**Supplied stack trace — key frames:**

```text
The following _TypeError was thrown while handling a gesture:
Null check operator used on a null value

#0 StatefulElement.state (package:flutter/src/widgets/framework.dart:5951:44)
#1 Navigator.of (package:flutter/src/widgets/navigator.dart:2949:38)
#2 _ManagementStaffPaneState._report.<anonymous closure>.<anonymous closure>
   (package:xorder_pos/features/admin/presentation/management_staff_pane.dart:402:46)
#3 _InkResponseState.handleTap (package:flutter/src/material/ink_well.dart:1224:21)

Handler: "onTap"
Recognizer: TapGestureRecognizer
```

**Suspected mechanism, not confirmed:** The onTap callback calls `Navigator.of(context)` with a stale or unmounted `BuildContext`, perhaps after a dialog closes/rebuilds. Inspect line 402 and its surrounding `_report()` widget/dialog lifecycle before deciding on a fix. `StatefulElement.state` failing is consistent with accessing state on an unmounted element, but the actual cause must be verified.

**Investigation steps for Claude**

1. Open `xorder_pos/features/admin/presentation/management_staff_pane.dart`, especially `_report()` and line ~402, including parent navigator/dialog composition.
2. Reproduce the exact user action, note which control was tapped, whether a dialog was already dismissed and whether async work completed in between.
3. Check context ownership, `mounted`/`context.mounted`, `Navigator.of` vs root navigator, dialog-local builder context and any delayed callbacks.
4. Correct lifecycle/navigation use with the smallest valid change. Avoid a reflexive `mounted` check if the wrong context is structurally captured; choose the proper active navigator/context.
5. Add a widget regression test reproducing tap, dialog dismissal/navigation and rapid repeated taps where relevant.

**Acceptance / QA**

- [x] The specific Staff Management action works and no framework error occurs. — *regression test reproduced the exact `Null check operator used on a null value` before the fix and passes after*
- [x] Repeated taps, dismiss-before-callback, route changes and async completion are safe. — *three tests: pane removed while the dialog is open, plain dismiss, and three rapid taps*
- [x] Desired navigation/dialog result is preserved. — *Close dismisses the dialog and leaves the pane in place*
- [x] No `Null check operator used on a null value` from this flow in debug/test runs. — *full POS suite passes*

---

### XORD-011 — Business-defined roles, not automatically seeded business roles

**Decision:** XOrder exposes a **fixed system permission catalog**, but the owner defines the business roles and assigns permissions. Do not auto-create roles named Cashier, Manager, Waiter or Supervisor for each business. The verified owner retains administrative authority independently of a generated "Owner" role.

**Requirements**

- Owner can create, rename, describe, update and retire custom roles, with unique names within the business.
- Owner can assign permissions from grouped modules: POS, orders, customers, menu, inventory, finance, Back Office and staff administration.
- Staff may be assigned existing business roles; role changes affect all assigned staff according to session refresh rules.
- Enforce authorizations server-side and locally where offline actions must be authorized. Prevent privilege escalation and cross-business access.
- Do not delete a role assigned to active staff without safe reassignment. Migrate pre-existing role assignments without accidentally elevating or locking out users.
- Record role and permission changes in the audit log.

**Acceptance**

- [ ] A new business gets no auto-generated cashier/manager/waiter roles.
- [ ] Owner can define arbitrary role names with explicit permissions.
- [ ] Permissions govern actual API/actions, not just menu visibility.
- [ ] Active users with changed permissions are refreshed/revoked under documented policy.
- [ ] Migration retains existing staff access safely and is tested.

### XORD-012 — Deleted menu products continue to appear

**Observed:** After deleting a menu item, it remains visible in menu/POS. Source not yet diagnosed. Candidate causes include stale UI cache, filtering only `is_active`, local/offline copies or sync rehydration.

**Decision:** A user-triggered **Delete** must physically remove the product row; `is_active=false` is the **separate Disable** action, not a substitute for deletion.

**Requirements**

- Inspect UI action, database command, POS offline store, cloud persistence, caches and sync contract end-to-end.
- Delete the catalogue product row from its authoritative store using an audited, transactional path; propagate deletion through replication.
- A sync tombstone/deletion event may remain as **metadata** after the product row is removed, with retention sufficient to reach previously disconnected tills.
- Keep historical paid order lines, invoices and financial reports intact via immutable sale snapshots/references designed for deletion.
- Avoid accidental resurrection on retry, restart or device reconnection; distinguish disable/enable from delete in UI and APIs.

**Acceptance**

- [ ] Product row is physically absent after successful deletion.
- [ ] POS views and new-order search omit the product immediately and after relaunch.
- [ ] Offline till reconnecting later applies the deletion and does not recreate it.
- [ ] Historical invoice/order data remains correct.
- [ ] Disabled products remain persisted and may be enabled again independently.

### XORD-013 — Physically delete a category and its related products

**Decision:** Deleting a category should delete the category row and all product rows **exclusively owned by it**. Do not merely mark them inactive.

**Requirements**

- Show a confirmation naming the category and exact affected product count; warn of the removal.
- Validate dependencies/ownership first. If products may belong to multiple categories, confirm the approved policy before deleting shared products; do not remove products still used by other categories without explicit product approval.
- Delete related products and category in one transaction or equivalent fault-safe workflow; protect referential integrity.
- Publish reliable deletion events to sync offline and cloud replicas. Preserve sales history and audit identity.
- Prevent duplicate deletion events from causing misleading errors or old devices reintroducing deleted records.

**Acceptance**

- [ ] User sees actual affected count and explicit irreversible-action warning.
- [ ] Category and exclusive products physically disappear from the database on success.
- [ ] No partially deleted category/product group after failure.
- [ ] Historical transactions and multi-device sync remain valid.
- [ ] Shared-category/product edge cases follow an approved business rule.

### XORD-014 — Inspect `pos_products` / `pos_categories` relationship in both databases

**Observation from tester:** The database appears to have no relationship between `pos_products` and `pos_categories`; this is a claim to **verify**, not yet an inspected schema result.

**Requirements**

- Inspect migrations, current live schema, constraints, indexes and ORM/entity mappings in **POS local/offline** and **Cloud** databases. Determine if relation is one-to-many or many-to-many and whether association currently lives in a junction table or code.
- Audit existing rows for dangling references, mismatched tenant/branch IDs and category-less products.
- Plan safe forward-only migrations with preflight diagnostics, backups, ordering and rollback/recovery strategy. Do not run destructive cleanup blindly.
- Add foreign keys/uniqueness constraints as appropriate to the confirmed domain model. Define `ON DELETE` actions only after resolving XORD-013 and historical sale references.
- Verify cloud sync carries stable IDs, relation updates and deletion events without violating referential integrity.

**Acceptance**

- [x] Relationship model documented from actual schemas, not guessed. — *see section 8: both databases have the foreign key*
- [ ] Offline/cloud migrations enforce appropriate constraints without data loss.
- [ ] Existing valid associations are preserved; broken data is reported and handled deliberately.
- [ ] Category/product delete and sync tests pass across both databases.

### XORD-015 — Link payment methods to financial accounts

**Observed:** Payment methods have no associated financial account in the tested setup. Inspect actual schema and workflow before confirming root cause.

**Expected behavior**

- Back Office supports managing financial destination accounts, e.g. branch cash drawer, bank settlement account and electronic wallet.
- Each active payment method gets a **default destination account** valid for the same business/branch. Owners/authorized managers configure mappings; cashiers ordinarily cannot change mappings during payment without explicit permission.
- On payment capture, record an immutable financial movement linking order, invoice, payment, method, destination account, amount/currency, staff and time.
- Split payments produce a separate movement per captured tender. Refunds/reversals generate corresponding traceable compensating entries; never rewrite past payment history.
- Changing the default destination must not retroactively change earlier movements. Disabled accounts cannot receive new payments.
- Use idempotency keys/transaction boundaries to prevent double posting on retries or offline/cloud synchronization.
- Distinguish an **operational destination** (cash drawer/bank/wallet) from a formal ledger account; investigate current accounting model and map appropriately, rather than treating them as identical by assumption.

**Acceptance**

- [ ] Every enabled method used for payment has a valid configured account, or a clearly approved fallback rule. — *stage 1 lets a method have a default account (per branch, with a business-wide fallback); no payment reads it yet, and a method with none behaves as before. Not met until stage 2 or an approved fallback.*
- [x] Authorization and tenant/branch isolation enforced for mapping changes. — *stage 1, cloud `FinancialAccountsTest` (24: a `settings.update`-only role gets 403 on accounts and on defaults, another restaurant's account is 404, another restaurant's branch/method/account is 422); POS `data/financial_accounts_test` (PostgreSQL, 25: cashier and cloud till refused, another restaurant's branch refused) and `admin_grants_enforced_test`/`till_grants_enforced_test` against real roles. Mutation-checked: gating the writes on `settings.update` fails two cloud tests.*
- [ ] Cash, card and wallet payments post to their configured destinations.
- [ ] Split payment, refund, retry and offline sync have exact non-duplicated movements.
- [ ] Account setting changes do not rewrite historical payments/reports. — *true by construction in stage 1 (no payment or report reads an account, no payment table was touched), but no test proves it; stays open for stage 2.*
- [ ] Reconciliation totals match captured/settled amounts and known processing states.

**Amended 2026-10-26 (owner):** a payment method now offers, and accepts as its default, only accounts of its own kind (cash→cash, card and the platform's external→bank, wallet→wallet on both sides — the platform gained a `wallet` payment-method kind; other kinds any); enforced in the POS repository and the cloud API, hidden in both screens, a pre-existing mismatch kept and marked. See `docs/features/finance-account-kind-per-method/`. Tests: POS `account_kind_rules_test`, `management_accounts_pane_test`; cloud `FinancialAccountsTest` (28). The POS PostgreSQL repository tests were written but **not run** here; the dashboard panel builds but was **not viewed**.

**Decision still needed:** Can the cashier override the configured default destination during payment with a specific permission, or must the destination always be determined from Back Office? **Recommendation:** Back Office default, exception with elevated permission and audit log.

### XORD-016 — A local licence shows no sign that a device used the key

**Reported by:** Amer, while testing `http://admin.localhost:8080/pos/licences/24` (a local licence): *"even if it's local only it should show that the device used the key."*

**Actual:** the Devices card said a local licence's tills never reach the platform, so there was nothing to list. The platform kept one fact about use, the first-activation date.
**Expected:** the page shows that a device used the key, which device, when, and how many times.
**Classification:** Enhancement. **Priority:** P2.

**Acceptance / QA**

- [x] Each device that uses the key is recorded once, with first use, last use and count. — *`LicenceActivationsTest`*
- [x] History survives a renewal that keeps the key; a rotated key starts clean. — *tested*
- [ ] The local licence's Devices card lists them (and says so when the key was used before devices were recorded). — *built and compiled into the Docker web app; not viewed in a browser*

### XORD-017 — A one-device licence accepts a second device

**Reported by:** Amer: *"but it is for 1 device only"*, after being told a second device would simply be listed.
**Actual:** activation succeeded for any number of devices; `max_terminals` was advisory.
**Expected:** a licence sold for 1 device refuses a second one.
**Classification:** Security / Enhancement. **Priority:** P1.

**Acceptance / QA**

- [x] A new device is refused with `409 licence_seats_full` once every seat is in use; the refused device is not recorded. — *API tests, and the same request against the running Docker app*
- [x] A device already recorded can always come back (renewals re-fetch under the same key); a downgrade never locks one out. — *tested*
- [x] An upgrade renewal makes room. — *tested*
- [x] Cloud licences are not counted (their tills share one key; counting would refuse working tills). — *tested; owner decision still open*
- [x] An admin can release a device to free its seat. — *API tested (audited); the Release button is UI, not browser-tested*
- [x] The till shows a clear message for a full licence. — *`LicenceSeatsFull` is mapped from the 409 (`offline_licence_activation_test`), and `licence_seats_full_test` (4) drives the real Licence screen: the sentence appears in English and Arabic with the device count, a missing count still gives a whole sentence, and it is not shown as success. A till built before this change still shows a generic "server refused" until it is rebuilt*

### XORD-018 — Licence page "Client" card values are misaligned in Arabic

**Reported by:** Amer (screenshot of `/pos/licences/24`): *"Fix alignment here also."*
**Actual:** labels sat on the right but the identifier, phone and email sat on the left of their cells.
**Expected:** values on the same edge as their labels; the text still reads left to right.
**Classification:** UI bug. **Priority:** P3.

- [ ] Values align with their labels in Arabic and English. — *one style rule in `LicenceDetails.vue`; there is no front-end layout test, so it needs a visual check*

### XORD-019 — POS Orders screen misaligned in Arabic

**Reported by:** Amer (screenshot of the back-office Orders screen): *"Work on fix alignment for this screen."*
**Actual:** the time pressed against the order type (`07:15صالة`), the item quantity touched the item name, the Excel button floated in the middle of the header, and the reprint button read "إعادة طباعة الفا…".
**Expected:** every value under its heading on the language's start edge, readable labels, the export button at the end of the header.
**Classification:** UI bug. **Priority:** P2.

- [x] Time, invoice and quantity sit on the start edge under their headings in Arabic, and unchanged in English. — *10 widget tests with the bundled fonts; 8 fail on the old code*
- [x] The Excel button is at the end of the header in both languages. — *tested*
- [x] The reprint label is shown whole. — *tested with the real font*

### XORD-020 — POS Orders search box is a thin strip

**Reported by:** Amer: *"search input is so small, why this?"*
**Actual:** the field was given the chips' height but drew its border around one line of text, pinned to the top.
**Expected:** the same height as the filter chips, with the whole hint readable.
**Classification:** UI bug. **Priority:** P3.

- [x] The search field expands to the chips' height with its text centred, and is wide enough for the hint. — *2 widget tests; the height test fails on the old code*

### XORD-021 — Tenant / business logo management and synchronisation

**Reported by:** Amer, as "XORD-016" (that number was already taken by the licence-devices finding, so it is recorded here as XORD-021).
**Asked for:** (1) offline Back Office: upload, show, replace and delete the business logo, kept across restarts, PNG/JPG with size and dimension checks, only for the owner or `business.branding.manage`; (2) cloud: a database field, an API that stores and returns the logo, and the logo in the POS bootstrap so changes reach an offline POS by sync; (3) POS: show the logo from the restaurant settings, keep a local copy for offline use, refresh when it changes, show a default image when there is none, and never let a logo problem affect the POS. "Reuse existing branding; no duplicate fields or APIs; decide file reference, URL or binary asset."
**Classification:** Enhancement. **Priority:** P2.

**What already existed (investigated first):** cloud `restaurants.logo_url`, set by the dashboard profile through `POST /api/uploads/image` (re-encoded to WebP, 4 MB cap) and carried to tills in the bootstrap `branding.logo_url`. The POS ignored it and showed a bundled mark. So **no new cloud field, endpoint or upload path was added**; the gap was the bundle never telling tills the logo had changed, and the POS having nowhere to keep one.

**Decision (file reference vs URL vs binary):** cloud keeps the URL it already has; the **POS keeps the image bytes** in `pos_restaurants` on the branch database, because a URL is unusable offline and the branch database is already shared by every till on the LAN. Offline installs author the bytes directly; cloud tills download them after each bundle.

- [x] No second logo field or API on the cloud. — *the existing `logo_url` and upload endpoint are reused; the only cloud change is a config-version bump*
- [x] A logo change on the cloud reaches tills. — *`Restaurant::updated` bumps `pos_config_version` only when `logo_url` or `brand_color` actually changed; `PosBrandingVersionTest` (6: new logo, removed logo, same logo posted back, unrelated field, super-admin path)*
- [x] The POS stores the image locally and shows it with no network. — *migration 58 (`logo_bytes`, `logo_mime`, `logo_source`, `logo_remote_url`, `logo_fetched_url`, `logo_updated_at`), `businessLogoProvider`, `StartLogo`; PostgreSQL suite `test/data/business_logo_test.dart`*
- [x] Add, replace and delete in the offline Back Office, owner or `business.branding.manage` only, audited. — *`PostgresBusinessLogoRepository`; refused for `settings.manage` alone, for a cloud till and without the administrator credential; the audit row holds sizes and type, never the image*
- [x] PNG/JPG only, with size and dimension validation. — *`BusinessLogoRules.inspect` reads the file's own header (not its name): 2 MB cap, 64–4096 px per side, a real PNG/JPEG; 21 unit tests incl. truncated and mislabelled files*
- [x] The owner keeps authority on existing installs. — *migration 59 grants the key to the `owner` role only; idempotent; managers and custom roles do not gain it*
- [x] The POS downloads the platform's logo and keeps the old one if the download fails. — *`LogoSync` (after every bundle and every pass, so a failed download is retried); address as sent, then the same path on the platform the till talks to; refuses non-http(s), non-images and oversize; guarded against a newer bundle landing mid-download*
- [x] No logo (or a corrupt one) shows the default mark and never breaks the start screen. — *`StartLogo` falls back to the bundled mark on none, on undecodable bytes, and the provider never throws*
- [x] A platform that says "no logo" clears its copy but not one chosen on the till; an older platform that sends no `branding` block changes nothing. — *tested*
- [ ] Looked at in the running app (Settings › General card, start screen) in English and Arabic. — *the widget tests pass; not seen on screen*
- [ ] Sent to a real cloud, end to end (dashboard upload → bundle → till). — *each half is tested; the whole chain was not run*
- Not covered by "no cross-restaurant access": the cloud serves logos from the public disk under unguessable file names, and a bundle only ever names the caller's own restaurant. Nothing here changes that, and it is not new.
- Out of scope, noted: receipts still print no logo (`receipt_document.dart`); the cloud has no `business.branding.manage` capability, so on the dashboard the profile stays restaurant-admin only.

### XORD-022 — Back Office navigation restructuring and UX improvements

**Reported by:** Amer, as "XORD-018" (that number was already taken by the licence-page Client card finding, so it is recorded here as XORD-022; the sub-items are therefore 022-A to 022-F, reported as 018-A to 018-F).
**Module / platform:** XOrder POS — Back Office (Flutter, Windows/macOS). Not the cloud dashboard.
**Classification:** Epic, UI/UX enhancement with a security part (F). **Priority:** P1 for the epic (A, B, D, F High; C, E Medium as reported).
**Related:** XORD-008 (Back Office entry is permission-controlled), XORD-011 (business-defined roles), XORD-005 (language setting).

**Problem (as reported):** the Back Office top navigation has duplicated functionality, unclear menu classes, inconsistent dropdown structures and too many top-level items. It must be reorganised for usability, discoverability, consistency and maintainability **while keeping every existing function**, in Arabic (RTL) and English (LTR), responsive, and respecting role-based access.

**Scope:** remove duplicate entries; group features logically; improve labels; separate application settings from user-account actions; improve dropdown design and interaction; enforce permission-based visibility; **preserve all existing routes and functionality**. No business logic, database operation or workflow changes.

**Status of the facts below:** "Observed" and "Proposed" are the reporter's description. They were checked against the source on 2026-10-25; the result, including what could not be confirmed, is in section 8.3 (XORD-022) and `docs/features/back-office-navigation/NAVIGATION_INVENTORY.md`. The proposal is not to be built from this text.

#### 022-A — Remove duplicate navigation entries (High)

**Observed:** Payment Methods under both Reports and Finance; Employees under both Reports and People; Orders and Invoices settings more than once under Settings; Language and theme controls with overlapping entries.
**Expected:** each management feature has one primary location; where a subject exists in two modules the entries are told apart by purpose (for example Finance → Payment Methods = manage; Reports → Payment Methods Report = analyse).

- [ ] All existing navigation entries and their destinations are audited; duplicates and their intended function are documented. — *done as a written audit (`NAVIGATION_INVENTORY.md` sections 2–4); no automated check, so unticked*
- [ ] Genuinely redundant links are removed; management and reporting pages are clearly distinguished; all unique functionality stays reachable. — *Finance › Payment methods merged into Reports › Payment methods, its payment ledger kept (`finance_panes_test`, 2 tests); the till's "Orders & invoices" line renamed "Order history" so it no longer reads as the settings page; Employees/Staff made one word. Unticked: the Sales / order-history entries are still more than one and wait on your decision*
- [ ] Existing routes are kept or given safe redirects; direct navigation and deep links still work.
- [ ] No duplicated destination remains without a documented reason. — *labels: `back_office_shell_test` "every pane has a label…" allows only Sales, Payment methods, Employees to repeat (checked to fail without the allowance). Destinations: Switch user and Lock both open the lock screen on purpose (two intentions), documented in `app.dart` and `settings_bar_test`. Unticked: Order history is still reachable from Sales and from Settings*

#### 022-B — Reorganize the menu hierarchy (High)

**Observed:** Dining Areas sit under Menu; Customers and Employees share a generic People label; System and Settings overlap.
**Proposed structure (a proposal, not a decision):**

| Main menu | Sub-menus |
|---|---|
| Dashboard | Business Overview |
| Sales | Orders, Invoices, Refunds |
| Menu | Products, Categories, Modifiers, Combos |
| Inventory | Inventory Items, Stock Availability, Units, Stocktaking |
| Purchasing | Purchase Orders, Suppliers, Purchase Invoices, Supplier Payments |
| Finance | Financial Accounts, Cash Registers, Revenue, Expenses, Payment Methods, Settlements |
| People | Employees, Roles & Permissions, Shifts, Customers |
| Reports | Sales, Products, Employees, Payment Methods, Inventory |
| Management | Dining Areas & Tables, Devices, Synchronization, Backups, System Logs |
| Settings | General, Orders, Printing, Language, Appearance, Business Settings |

The existing routes and features are mapped **first**; destinations that do not exist (for example Refunds, Settlements, Supplier Payments, Revenue, Expenses may not) are reported as missing, **not built to fill a menu**. Several proposed entries lean on other findings that are still open (XORD-011 roles, XORD-015 financial accounts).

- [ ] A complete Current → Proposed mapping exists, and the structure is confirmed with Amer before significant structural change. — *mapping written (`NAVIGATION_INVENTORY.md` section 6); Amer's confirmation is pending (nine decisions, section 7)*
- [x] Every existing functional page is kept, each with one clear primary location; no duplicate pages are created. — *`back_office_shell_test` (every page the bar reaches lays out, en and ar; every pane has one tab and a label). Caveat: Finance's Payment methods page was merged into the report by your decision, with its ledger kept; Dining areas & tables moved to Management*
- [x] Navigation history and back behaviour are preserved; Arabic and English structures both work. — *`settings_bar_test` (a line opens its page and Log out returns to where Admin Mode began; entered by the chord from Orders it exits to Orders; the bar in Arabic; 1100 px fit in en and ar), `admin_entry_test` (Log out returns to where the till was)*
- [ ] No change to business logic, database operations or workflows; navigation documentation updated. — *no migration, no repository or cloud change; the full POS suite is green. Unticked until the review phase reads the diff, and the feature folder is brought up to date*

#### 022-C — Navigation labels and terminology (Medium, localization)

**Observed:** النظام (System) vs الإعدادات (Settings) is ambiguous; الأفراد (People) does not say what it holds; المنيو mixes Arabic and English-derived terms; some entries name an action and others a module.

- [ ] All Arabic and English labels are audited and made consistent, descriptive and natural for restaurant staff; the English carries the same meaning.
- [ ] Existing localization resources are reused; no hard-coded labels. — *new labels are `AppStrings` getters in both languages (`paneDining`, `tabAccount`); not yet checked for hard-coded labels across the whole bar*
- [ ] Labels stay readable (no clipping) at supported sizes; navigation, page titles and breadcrumbs agree. — *the bar fits at 1100 px in en and ar with the longer Arabic words (`settings_bar_test`); titles come from the same function as the bar's lines. Not seen on screen*

#### 022-D — Separate Settings from user-account actions (High)

**Observed:** the Settings dropdown mixes business configuration, system settings, user preferences and account actions: language, theme, Switch User, Order and Invoice settings, Printer and Cash Drawer, User Settings, About XOrder.
**Expected:** *Application settings* = General, Business Configuration, Orders & Invoices, Printing & Cash Drawer, Language, Appearance. *User account menu* = current user, Switch User, Lock POS, Sign Out, About XOrder. Language and appearance have **one canonical** configuration destination; a quick toggle is allowed only if it writes the same underlying setting.

- [x] Account actions are out of the Settings dropdown; a dedicated account menu shows the signed-in user's identity and holds Switch User and Sign Out (and Lock POS). — *`settings_bar_test`: a cashier gets the account menu (name, Switch user, Lock, About; no Log out) and Settings has no Switch user; the owner offline and on cloud: the account menu is last and lists exactly name, Switch user, Lock, Log out, About; the same in Arabic*
- [x] Existing session-switching and lock behaviour is unchanged. — *`settings_bar_test` "handing the till over" (Switch user and Lock both go to the lock screen, as Switch user did), Log out tests above; `admin_entry_test`*
- [ ] No duplicate language or theme entries; application settings stay permission-controlled. — *not done: per your decision the quick toggles stay in Settings beside the Language and Appearance pages*
- [ ] Account actions stay reachable without exposing restricted Back Office features; mouse and keyboard both work. — *a cashier reaches the account menu and sees no back-office line or Log out (`settings_bar_test`); mouse (tap) is tested, keyboard is not*

#### 022-E — Dropdown navigation design (Medium)

**Observed:** inconsistent widths, grouping and hierarchy; long lists with no separation; the active sub-menu is not clear.

- [ ] One reusable dropdown component with consistent width, spacing, typography, grouping and optional icons across all main menus.
- [ ] Hover, focus, selected (active sub-menu) and disabled states are distinct; labels are not clipped.
- [ ] Open and navigate by keyboard; Escape closes; menus close after navigation and on outside click.
- [ ] A dropdown never renders off the available screen; RTL and LTR alignment are both correct.
- [ ] Checked at the supported desktop resolutions and window sizes.

#### 022-F — Permission-based navigation visibility (High, security)

**Expected:** visibility follows the signed-in user's **effective permissions**; the verified owner keeps administrative access; custom roles are created by the owner; every destination has a permission; unauthorized entries are hidden and a parent with no accessible child is hidden; permissions are evaluated within the right business and branch scope. Hiding is not the control: direct routes, services and the API stay protected.

- [ ] A permission is defined for every navigation destination, reusing existing permission identifiers (for example `admin.enter`, `settings.manage`, `business.branding.manage`). — *current mapping documented; 21 panes have no gate beyond the door, none changed yet*
- [ ] Unauthorized entries and empty parents are hidden; owner access to the supported administrative functions is preserved.
- [ ] Direct route access by an unauthorized user is refused, and authorization is enforced at the repository/service/API boundary, not only in the menu.
- [ ] Updated role permissions take effect under the established session-refresh policy.
- [ ] Tested as owner, cashier, manager and a custom role; tenant and branch isolation verified; no existing security control weakened.

#### Work order requested

1. Inspect the current Flutter navigation and list every top-level and dropdown item with its route, permission, page title and localization key.
2. Produce the Current → Proposed mapping and the duplicate/ambiguous list; **confirm the hierarchy with Amer before significant structural change**.
3. Build the approved structure with reusable components, reusing existing routes and permission services; do not touch unrelated business logic.
4. Add navigation and widget tests; check Arabic RTL and English LTR, several window sizes, and the role scenarios above.
5. Document the change and update the navigation documentation.

**Definition of done (epic):** all six sub-items addressed; existing functionality still reachable by authorized users; no unintended duplicates; Arabic and English both correct; mouse and keyboard dropdowns; permissions enforced; no navigation regression; relevant automated tests pass; the final UI visually reviewed; documentation updated.

**Deliverables:** current navigation inventory; Current → Proposed mapping; list of modified components and routes; permission mapping; test results; before/after screenshots of the affected menus; remaining limitations and unresolved decisions.

**Leads already in this file (not a diagnosis):** the top bar shows the Back Office menus only after Admin Mode sign-in and the permission that fits is `admin.enter`, and Admin Mode now asks non-cashiers for a password (see XORD-008 in section 8). Any new menu gating has to be read against that and must not add a second path into Back Office. Venue-model note: a cloud-kitchen or food-truck branch has no dining areas, and several proposed entries (Dining Areas & Tables, Shifts, Cash Registers) depend on feature flags or plan, so "hide when not applicable" is a separate question from "hide when not permitted" and the mapping should record which one each entry needs.

### XORD-023 — Interface language follows the content language

**Found:** while closing XORD-005 (2026-10-25). **Classification:** Bug / design. **Priority:** P2.
**Actual:** for a restaurant whose content language is a single language, the cloud dashboard's interface language is forced to it (existing behaviour, not caused by XORD-005). Where it is forced is **UNVERIFIED** (not traced).
**Expected (XORD-005 rule):** the interface language is the user's own choice and stays separate from content-language availability; an owner of an Arabic-only menu can read the dashboard in English.
**Status:** not started. Cloud SPA behaviour change; needs owner approval of the intended rule (per user or per restaurant) before code.

- [ ] An Arabic-only restaurant can use the dashboard in English and an English-only one in Arabic, with RTL/LTR correct.
- [ ] Content forms still follow the content-language setting.
- [ ] A test or browser check proves both.

---

### XORD-024 — Print the business logo on the receipt
**Reported 2026-10-26 (owner, with a screenshot of the Arabic preview):** the logo should appear on the receipt; if XOrder is shown, it goes in the bottom footer. Specification, decisions and code references: `docs/features/receipt-logo-and-layout/FEATURE.md`.
**Decisions (owner, 2026-10-26):** prints automatically once a logo is set, with a per-till switch (Settings › Printer & cash drawer, on by default); a reprint uses the current logo; XOrder only in the footer.

- [x] The logo is the first block of the header, above the name and below any REPRINT or REFUNDED stamp. — *`receipt_document_test` "the logo (XORD-024)"*
- [x] Printed size is within the content width and 120 dots (80 at 58 mm), never enlarged, centred; the QR, name and the rest stay. — *`receipt_logo_raster_test`: "the logo alone", "the slip with a logo"*
- [x] No logo, an empty one, an undecodable one or the switch off prints exactly as before, and printing still succeeds. — *`receipt_document_test`, `receipt_logo_raster_test`, `receipt_print_test` ("and not when this till is set to leave it off", "a logo nobody can decode…")*
- [x] A light-coloured or transparent logo is not lost. — *`logo_bitmap_test`, `receipt_logo_raster_test` "what a bad or pale logo does"; mutation-checked*
- [x] The switch shows, defaults on, saves, survives other printer edits; an old config file reads as on. — *`printer_settings_test` "print logo on receipts (XORD-024)"; mutation-checked*
- [x] Offline and cloud tills read the same stored logo; a reprint prints the current one. — *`receipt_logo_provider_test`; `receipt_print_test` "a reprint prints the logo the till holds now"*
- [x] The preview shows the logo, and none when the switch is off or there is no logo. — *`receipt_print_test`, `receipt_amounts_test`*
- [x] XOrder is named nowhere above the footer. — *`receipt_document_test` "XOrder is only in the footer"*
- [ ] **The logo is legible on a real 80 mm and 58 mm thermal printer, in Arabic and English.** — *needs a person; not a test*
- [ ] A queued receipt keeps the logo it was first printed with. — *true by design (the queue stores the finished job bytes); no test of its own*

### XORD-025 — Receipt amounts do not line up in Arabic; currency label off-centre
**Reported 2026-10-26 (owner, screenshot):** "there is an alignment issue". Investigated: in Arabic the amount column's figures shared a left edge instead of a decimal point (`450.00` over `63.00`), and the currency under the total sat under the middle of the figure.

- [x] Amount rows, item prices and the items heading end at one dot, in Arabic and English, at 80 and 58 mm. — *`receipt_amounts_test` (bitmap measurement); the four old behaviours were put back and each made a test fail*
- [x] The code under the total ends where the figure ends. — *`receipt_amounts_test` "the currency under the total"; mutation-checked*
- [x] The preview agrees with the print. — *`receipt_amounts_test` "the preview" (Arabic and English). It found a real bug (the code wrapped); fixed*
- [x] Nothing is cut off with a long Arabic name and a seven-digit total. — *`receipt_amounts_test` "nothing is cut off"*
- [ ] Looks right on paper. — *the tests run in the test font; widths on a real roll differ. Needs a person*

### XORD-026 — Receipt shows the currency only on the total
**Reported 2026-10-26 (owner, screenshot):** "miss to show currency in some fields". The printed slip had left the code off on purpose (commit `a6f5fe5`, 2026-10-25); the owner reversed that.

- [x] Every amount (line prices, subtotal, discount, service, each VAT line, each tender line, paid, change) ends with the currency code. — *`receipt_document_test` "the currency is printed beside every amount (XORD-026)"; the change line shares the code path, no sale in the suite gives change*
- [x] Figures are unchanged to the minor unit; only their text changed; the total keeps its figure and code apart. — *same group*
- [x] The price column fits the longest expected figure and code (190 dots). — *by arithmetic and the "nothing is cut off" test in the test font; **not seen with the real font***

### XORD-027 — VAT set to 0 still charged and printed at 14%
**Reported 2026-10-26 (owner, receipt screenshot, order `MAIN-2026-000006`):** "it show taxes as %14 even i make it 0". Root cause (confirmed, reproduced to the piastre): the Taxes pane's VAT box saved only `vat_bp`, but a ticket is taxed at the **default tax group** whenever one exists, and every offline setup seeds one at 14% (`TaxConfig.defaultTaxGroup`). Full report: `docs/harness/investigations/vat-box-zero-still-charges-14-and-inclusive-option.md`.

- [x] Saving the VAT box moves the default tax group's rate (0, 15, 12.5%); other named groups are untouched; with no default group it still saves. — *PostgreSQL `postgres_catalog_admin_test` "money rules" (setting VAT to 0…, any other rate…, only the default group moves…, with no default group…); 6 new tests pass against the local test database; with the UPDATE neutralised they fail with `Expected: [0] Actual: [1400]`*
- [x] A rate over 100% is refused with a message, nothing written. — *same suite, "a rate over 100% is refused…"*
- [x] The audit event carries the default group's rate before and after. — *same suite, "the audit event records the group rate…"*
- [x] The VAT box shows the rate the till charges (the default group's), or the single rate when there is no group. — *`money_panes_ownership_test` (two tests); fails with the old seeding*
- [x] After saving, the running till re-reads the groups, so the next sale is priced at the new rate. — *`money_panes_ownership_test` "typing 0 over a 14% group…"; fails with the invalidation removed. The end-to-end sale after a save was not run*
- [x] A ticket is taxed at the default group, and `vatBp` alone is not enough (pins the mechanism). — *`tax_groups_wiring_test` "what a ticket is taxed at"*
- [x] The cart's VAT row names the rate actually applied, including 12.5% (it showed "13%"), and hides at 0%. — *`cart_totals_alignment_test` "the VAT row names the rate…" (3); fail with the old label*
- [ ] The printed receipt and the till screen show 0% after the owner types 0. — *needs a person on a running till; the receipt prints the tax line's own rate, so it follows from the tests above but was not exercised*
- [ ] Tills where the box and the default group already disagree (customers charged the group's rate) are reconciled. — *deliberately **not** done: nothing stored is rewritten; the pane now shows the group's rate. Owner decision needed if a one-off correction is wanted*

### XORD-028 — "Prices include tax" switch
**Reported 2026-10-26 (owner):** "i want to make option to make it inclusive if it there taxes". The engine, codec, parked tickets and reports already support inclusive pricing; **no screen sets it**, and a cloud till can never be inclusive (the bundle carries a per-rule `mode`, the till reads a top-level `tax_mode` that is never sent).
Needs a specification first (`/develop-feature`): wording so a bill does not read 1,050 + 126 + 144.42 = 1,176; whether the order records the mode (reports read the current setting); switching with open and parked tickets; whether service is taxed when prices are inclusive (owner/accountant); the cloud `tax_mode` (additive contract change, cloud first, `/release-check`).

- [ ] Offline Taxes pane switch. · [ ] Cart and receipt say the tax is included. · [ ] Cloud bundle delivers the mode. · [ ] Server and till totals agree for an inclusive rule. — *none started*

### XORD-029 — The POS PostgreSQL suite fails at the committed revision on a fresh database (fixed 2026-11-07)
**Already recorded in section 8.2 since 2026-10-25 ("about 476 tests, a combo-option foreign-key error, identically on an untouched copy of the last commit") but never given an id; filed here so it is tracked.** Re-measured 2026-10-26 (Claude, while testing XORD-015). `flutter test --tags integration --concurrency=1` against a **pristine `git archive` of `xorder-pos` HEAD a6f5fe5** (none of the uncommitted work, a new path so a new database, local PostgreSQL 16) ends `+677 ~1 -436`. Every failure is a foreign-key error raised by the suites' own `DELETE FROM pos_restaurants` cleanup, for example `update or delete on table "pos_products" violates foreign key constraint "pos_combo_options_product_id_fkey"` (239), `… "pos_staff" … "pos_orders_voided_by_fkey"` (149), `"pos_business_days" … "pos_orders_business_day_fk"` (22), `"pos_shifts" … "pos_orders_shift_id_fkey"` (3); once one suite leaves such rows behind, every later suite fails in `setUp`. The same run on the working tree with XORD-015 (and other sessions' uncommitted work) ends `+743 ~1 -456`: the same error kinds, no failure that is not also at HEAD apart from 20 tests that exist only in uncommitted work.
**Not known:** whether this is the local PostgreSQL version (cascade and `NO ACTION` ordering), the fixture, or a real schema ordering problem that would also stop a restaurant being deleted; whether it passed for the owner on another machine. **Expected:** `scripts/check.sh` green on a fresh database. **Needs:** `/bug-investigation`. Evidence: `docs/features/financial-accounts/TEST_REPORT.md`.
**Root cause (2026-11-07, Claude):** the test fixture, not the schema. (1) `pos_orders`, `pos_order_lines`, `pos_shifts`, `pos_business_days` and `pos_combo_options` reference users, products, days and shifts with **RESTRICT** on purpose (money history is never deleted with its cashier), so once any suite left a sale, shift or combo in the one shared database, every later suite's `DELETE FROM pos_restaurants` cleanup failed. (2) Suites that replay an old migration by deleting its `schema_migrations` row (55, 56) failed on `pos_staff`, which migration 62 renamed, and left the row deleted, so every later suite failed while migrating (`relation "pos_staff" does not exist`). (3) `installer_owner_test` and `pg_archive_restore_test` still named per-suite databases that `PgFixture.open` no longer creates.
**Fix (uncommitted → committed on `fix/xord-044-046-parked-check-versions`):** `PgFixture.open` rebuilds the shared database's schema once per test file (one isolate per file); the 55/56 replays run on a schema built up to just before them, as `pos_users_rename_test` already did; the two suites use `PgFixture.sharedName`; `pos_users_rename_test` accepts later migrations after 62.
- [x] `scripts/check.sh` is green on a fresh database. — *run 2026-11-07: analyze no issues; unit **3540 passed, 2 skipped**; PostgreSQL **1238 passed, 1 skipped, 0 failed**; "All checks passed."; test databases dropped (2 of 2)*

---

## 3. Shared implementation requirements

### Authorization and tenant isolation

- Centralize permission checks and enforce them at API/service boundary as well as UI; do not treat hidden buttons as security controls.
- Keep owner defaults, role grants, per-user grants, tenant/branch scope and audit logs consistent with the existing authorization model.
- Exercise least-privilege tests for cashier, owner, authorized manager and unauthorized staff.

### Localization, number entry and forms

- Reuse a single authoritative business content-language configuration for translatable forms; UI locale should not accidentally change persisted content requirements.
- Keep canonical numeric storage separate from localized display strings.
- Preserve translated values for disabled languages when editing.
- Check RTL layouts, Arabic numeral paste, keyboard composition and cursor behavior.

### Bulk operations and data integrity

- Confirm uniqueness scopes and batch limits. Decide atomic vs partial success intentionally, communicating results to the user.
- Protect against retries/duplicate submissions and preserve entered form data after a recoverable failure.
- Verify branch/tenant separation, offline queue behavior and conflict recovery where supported.

### Offline/licensing compatibility

- XOrder is intended to support both local/offline and cloud-related operation; **inspect actual deployed modes before assuming their storage topology**.
- Licence feature gating and updates should conform to the project's documented active plans and offline activation/update rules.
- Do not make critical POS order-taking depend unexpectedly on a live network request.

## 4. Suggested verification matrix

| Area | Core test coverage |
|---|---|
| POS order/customer | Existing selection; quick-create; cancel; cart retention; duplicate; offline |
| Order-type entitlements | All enabled; some disabled; expired/revised plan; direct navigation |
| Localization | Arabic UI; English UI; Arabic-only content; English-only; bilingual |
| Numeric forms | Arabic digits; ASCII; mixed; paste; decimals; leading zeros; caret |
| Bulk tables | 1, 10, max allowed, duplicates, invalid prefix/start, double-submit |
| Bulk categories | Multiple rows; duplicate names; mixed locales; failed validation |
| Back Office RBAC | Owner; granted employee; ungranted employee; direct route/API |
| Licence update | Authorized; denied; invalid values; audit; existing activation |
| Staff runtime exception | Exact tap; repeated tap; dismiss; route disposal; async transition |

## 5. Open product questions to resolve before implementation

1. **XORD-002:** Identify the four types from code and clarify handling of plan changes that invalidate all currently configured types. **Hide unavailable; allow only eligible selections and require at least one.**
2. **XORD-005:** Identify which forms are translatable and the canonical business content-language setting. **Owner can configure it.**
3. **XORD-006:** Confirm branch numbering scope, default naming and limit compatibility. Proposed `Table N`, max 100.
4. **XORD-007:** Confirm ordering/duplicate rules. **Batch must be all-or-nothing.**
5. **XORD-008:** Identify route and current permission key; include top menu and authenticated Home, never lock screen.
6. **XORD-009:** Confirm field allowlist, revision signing authority and offline delivery behavior.
7. **XORD-010:** Which exact Staff Management control triggered the trace, and what was UI state just before tap?
8. **XORD-013/014:** Confirm whether products can belong to multiple categories and resulting shared-product deletion policy.
9. **XORD-015:** Confirm destination account override policy and whether a formal general ledger already exists. **Answered 2026-10-26 (owner):** a cashier can pay into a different account than the method's default and an admin can transfer between accounts (both stage 2; whether the override needs its own permission is my recommendation, not confirmed); defaults are per branch with a business-wide fallback; accounts start from go-live. No formal general ledger exists in the code (searched cloud, web and POS).

If repository code or product documents answer these questions unequivocally, cite them in the implementation plan; otherwise ask Amer rather than inventing business behavior.

## 6. Definition of done / Claude output format

For each ticket, provide:

```markdown
### XORD-XXX — [Title]
- Status: Verified / Implemented / Blocked / Not reproduced
- Root cause or existing behavior: ...
- Files and modules affected: ...
- Design / business decisions: ...
- Implementation summary: ...
- Tests added or updated: ...
- Commands run and results: ...
- Offline / database / migration / permissions impact: ...
- Remaining risks or questions: ...
```

**Overall completion criteria:** All approved changes are reviewed; tests and builds pass or failures are documented; regression and security checks are performed; no unexplained data loss/permission widening; QA can verify each acceptance checkbox.

---

## 7. Future test findings

Continue numbering from **XORD-060**. Each new finding should record: module/screen, steps to reproduce, actual behavior, expected behavior, environment/build, relevant logs/screenshots, severity, and whether it is a bug or requested enhancement. Do not silently change IDs or merge distinct symptoms.

---

### XORD-059 — "Try again" after a failed database open leaves the sale screen broken

**Found:** 2026-11-07, manual re-test (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`, F5). **Type:** bug. **Severity:** P3, proposed.

- **Steps:** start a till build whose schema is newer than its database (or any boot whose first database read fails) → "تعذّر على الكاشير فتح قاعدة بياناته"; fix the cause (here: run the migration); press "حاول مرة أخرى"; sign in; open a sale.
- **Actual:** the start screen comes back, but the sale screen shows the original error ("relation pos_businesses does not exist") until the app is restarted.
- **Expected:** "try again" clears every failure cached by the first attempt (UNVERIFIED which provider holds it; likely the catalogue).
- [ ] After "try again" succeeds, the sale screen opens without a restart. — *not started*

### XORD-058 — A cloud till prints its own invoice number, not the one the cloud gives the sale

**Found:** 2026-11-07, owner comparing a till receipt with the local dashboard (manual test, `docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`). **Type:** bug (invoice integrity, cloud mode). **Severity:** P2, proposed.

- **Module:** POS cloud mode, receipt numbering (POS-BE-008: the server assigns the authoritative number).
- **Steps:** cloud till on `demo` branch 8, which already had 7 POS sales on the cloud; ring up and pay 5 sales.
- **Actual:** the receipts print `BR8-2026-000001` … `000005` as "رقم الطلب"; the cloud numbers the same sales `BR8-2026-000008` … `000012` (till outbox `server_invoice_number`). The paper a customer holds names a number the dashboard never shows; two tills on one branch would each start at 1 and print the same numbers. History and reprints on the till do use the server number once known (`postgres_order_history_repository.dart`, `coalesce(server_invoice_number, invoice_number)`).
- **Expected:** in cloud mode the first print shows the number the cloud will use, or prints PROVISIONAL with the till's local reference marked as such (`receipt_document.dart` already has the PROVISIONAL path for a sale with no number); the dashboard shows the same number the reprint does.
- UNVERIFIED: whether the local `invoice_number` is meant to be shown in cloud mode at all; behaviour with two tills.
- **Decision (owner, 2026-11-07):** the cloud's number is the invoice number; a cloud till's first print says PROVISIONAL.
- **Fix (branch `fix/xord-058-provisional-receipt`, `db3c2cd`, on top of `refactor/business-naming`, not pushed):** `PostgresOrdersRepository.submit` returns, on a cloud till, the platform's `server_invoice_number` (from `pos_outbox`) or null — and null is the receipt's existing PROVISIONAL path (`receipt_document.dart`); an offline till returns its own number as before. The till's local sequence still numbers the row. Voids are unchanged (the platform does not number them). This is what `SubmitOrderResult.invoiceNumber`'s own documentation already said.
- [x] A cloud till's printed receipt and the dashboard name a sale by the same number (or the receipt says provisional). — *`provisional_invoice_test` (3) passed, both cloud cases fail with the fix removed (mutation run); PostgreSQL pass 1244 passed; manual: receipt "مبدئية", cloud order 122 `BR8-2026-000013`, till history shows the cloud numbers (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`). The dashboard does not show invoice numbers at all yet (dashboard-order-receipt-parity).*
- **Follow-up (2026-11-07, commit `9f3d850`, merged into POS `development` `3052a53` on 2026-11-08):** the open receipt looks for the platform's number after every sync pass that delivered something and swaps it in (time kept, note becomes "synced"); a cloud till's history lists an unnumbered sale as PROVISIONAL / مبدئية in the row and the detail header. Offline tills unchanged.
- [x] The open receipt shows the platform's number once the drain brings it back. — *`receipt_platform_number_test` (3) passed; fails with the listener removed (mutation run); `provisional_invoice_test` "the open receipt finds the platform's number once it is back" (PostgreSQL) passed.*
- [x] Before delivery, a cloud till's history shows the sale as provisional, not its local number; an offline till shows its own number. — *`order_history_test` "a cloud till lists a sale the platform has not numbered as provisional" and "an offline till lists its own number" passed, the first fails with the label removed (mutation run); `provisional_invoice_test` "history says whether the platform has numbered a sale" (PostgreSQL) passed, fails with the flag forced (mutation run).*

### XORD-054 — Setup blames table rights when the admin cannot create the till's database user

**Found:** 2026-11-07, manual test of a cloud till against the local Docker cloud (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`), POS debug build `effdffb` on macOS, Claude driving the app. **Type:** bug (wrong message). **Severity:** P3.

- **Module:** POS setup wizard, step "جارٍ التجهيز" (local database).
- **Steps:** cloud till; enter a till database user that does not exist yet (`pos_till_cloudtest`) and an admin account without CREATEROLE (`pos_admin`, CREATEDB only); press "استخدم قاعدة البيانات هذه".
- **Actual:** "the server accepted `pos_admin` but refused: it has no permission to create tables in `xorder_cloudtest_db`… not a password problem". The database was owned by `pos_admin`, which could create tables (`has_schema_privilege(... 'CREATE') = t`). Creating the role by hand as a superuser made the same press succeed.
- **Expected:** the message names the real cause (the admin account cannot create the till's database user) and what to do (use an existing till user, or an admin with CREATEROLE).
- UNVERIFIED: which SQL statement failed (the wizard does not log it); the classification code that chose the message.
- [ ] Setup with an admin that lacks CREATEROLE and a new till user says the user cannot be created. — *not started*

### XORD-055 — A cashier added in the dashboard cannot sign in on a till until the next sync (up to 4 hours)

**Found:** 2026-11-07, manual test of a cloud till against the local Docker cloud (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`), POS debug build `effdffb` on macOS, Claude driving the app. **Type:** product question / UX. **Severity:** P3.

- **Module:** cloud staff and PINs → POS bootstrap (`PosConfigVersion`, `CloudSync`, `SyncSchedule`).
- **Steps:** add a cashier with a PIN on the cloud (the PIN path bumps `pos_config_version`); try to sign in on an already-running cloud till.
- **Actual:** "wrong username or PIN" until the till's next pass; idle passes are every 4 hours (owner decision 2026-09-27, `lib/data/cloud/cloud_sync.dart` `SyncSchedule.idle`). Restarting the app did not re-bootstrap; pressing the sync pill did, within 5 s.
- **Expected (proposal):** the dashboard says tills pick the change up on their next sync and how to get it now, or the till checks sooner after a staff change. Owner decision needed; the 4-hour rule is intentional.
- [ ] Decided: how fast a staff change must reach a running till. — *open*

### XORD-056 — The setup shortcut did not open the wizard on the welcome screen

**Found:** 2026-11-07, manual test of a cloud till against the local Docker cloud (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`), POS debug build `effdffb` on macOS, Claude driving the app. **Type:** bug, UNVERIFIED. **Severity:** P3.

- **Module:** POS welcome screen (`lib/features/setup/presentation/welcome_screen.dart`, `CallbackShortcuts` for Ctrl⇧S and ⌘⇧S).
- **Steps:** unconfigured till; click the window; press ⌘⇧S, then Ctrl⇧S.
- **Actual:** nothing; 12 taps on the logo opened setup.
- **Expected:** either shortcut opens setup.
- UNVERIFIED: the key presses were synthetic (computer control); a real keyboard may work. Needs a person to press the keys.
- [ ] A person confirms ⌘⇧S opens setup on macOS. — *not started*

### XORD-057 — A branch with no code gets an invented one on the till

**Found:** 2026-11-07, manual test of a cloud till against the local Docker cloud (`docs/testing/reports/2026-11-07-manual-pos-cloud-till-local.md`), POS debug build `effdffb` on macOS, Claude driving the app. **Type:** data / setup. **Severity:** P4.

- **Steps:** register a till on a cloud branch whose `code` is empty (local `demo` branch 8).
- **Actual:** registration succeeds; receipts are numbered `BR8-2026-000001`.
- **Expected:** a branch has a code before a till can register on it, or the dashboard asks for one; the till's fallback stays as a safety net.
- [ ] Registering a till on a branch without a code is refused or asks for one. — *not started*

Also seen (no id): the till's status bar shows a cloud cashier as "بلا دور" (no role); the till holds their permissions directly, so nothing is blocked.

---

### XORD-047 — The diner menu's line prices are trusted from the phone

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** bug (security, money), found by reading the source; **not exploited on production**. **Severity:** P1, proposed. **Status:** fixed on branch `fix/xord-047-server-priced-diner-orders` (`6e27fcd`, cloud repo, 2026-11-07), **not pushed, not deployed**.

- **Cause (from source):** `PublicOrderController::store` adds up the `line_total` each line submits; lines carry no item or option ids to price against (`apps/xorder-cloud/apps/api/app/Http/Controllers/PublicOrderController.php`, the total computation; the menu computes `line_total` on the phone, `apps/menu/src/App.vue:343`; `MenuItemPublicResource` sends no option ids).
- **Actual:** a modified request can set any price, including zero.
- **Expected:** the server prices every line from item and option ids (owner decision D2 in `docs/features/pos-incoming-cloud-orders/FEATURE.md`; stage S1 of its TECHNICAL.md).
- **Fix:** `App\Services\DinerOrderPricing` prices each line from `kind` + `menu_item_id`/`combo_id` + `option_ids` against `PublicMenuService::loadMenu()` (the menu the diner was shown), with the menu's arithmetic (`useCart.calculateLinePrice`: sale price; size replaces; add-on adds list price; combo base + extra), in minor units; names and labels from the menu in the diner's `lang`. Refused with 422 before any write: no ids ("please refresh", owner decision A5), another restaurant's item, unavailable, deleted, inactive-category or off-hours item, unavailable or foreign option, wrong choice count. `order_items` rows get `menu_item_id`, `unit_price_minor`, `line_total_minor`, `price_source = server`. Public menu adds option and combo-choice `id` (additive). Menu SPA sends the ids and `lang`; in system-only mode a refused order shows the server's reason and gives the basket back (it used to show success regardless). Tax, service and discounts still not applied to diner orders (unchanged).
- [x] A diner order with a tampered `line_total` is charged the server's price. — *`DinerOrderPricingTest::test_a_tampered_price_is_charged_at_the_menu_price` (cloud, SQLite); with pricing removed it and two more fail (mutation run)*
- [x] An unknown, foreign, unavailable or hidden item or option is refused and nothing is written. — *`DinerOrderPricingTest` (5 refusal tests)*
- **Checks run (worktree of the cloud repo, 2026-11-07):** the 9 suites that post orders, 70 passed before and after; `DinerOrderPricingTest` 9 passed; full suite `php -d memory_limit=2G vendor/bin/phpunit` **1157 passed** (with a throwaway `APP_KEY`, the worktree has no `.env`); `pnpm --filter @xorder/menu build` succeeds. **Not done:** the menu in a browser (the local Docker stack runs the main checkout, not this branch); PostgreSQL (tests are SQLite); merging with the other session's uncommitted guest-paging edits to the same `store()` method (a small manual merge); `/release-check` before any push.
- **Rollout:** a release day for every restaurant: a diner whose menu tab is older than the release is told to refresh once (A5).

### XORD-048 — Order details do not show the table

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** enhancement. **Severity:** P3.

- **Steps:** diner orders from T3's QR; admin opens Orders → ORD-61.
- **Actual:** list and details sheet show type "داخل المكان" but not "T3"; only the live board ties the order to its table.
- **Expected:** the table label shows in the list row and the details sheet.
- **Widened 2026-11-07 (owner: "this should be same as cashier recipet"):** the details sheet carries what the till's receipt carried. Spec: `docs/features/dashboard-order-receipt-parity/FEATURE.md`.
- **Status:** committed `c2191fb` and merged into cloud `development` 2026-11-08, **not pushed**.
- [x] The order API gives the table label on the list row and on the details request. — `tests/Feature/Pos/OrderReceiptSheetTest.php` (`test_a_till_sale_shows_what_its_receipt_carried`, `test_the_list_is_unchanged_and_the_sheet_keeps_every_list_key`)
- [x] The details request returns the receipt's facts from the stored order: invoice number, till, cashier, table and area, subtotal, discount, service, VAT, total, refunded and each payment; a diner order returns none of the till's fields; another business's order is 404; staff without order access are refused; every list key is unchanged. — `OrderReceiptSheetTest` (5 tests)
- [ ] The list row and the sheet show them on screen, in Arabic and English. — built (`pnpm --filter @xorder/web build`) and looked at in the built-in browser against a stubbed API (till sale and diner order, both languages); not an automated check, and not against a real API

### XORD-049 — Table orders have no Complete action on the Orders page, and no hint why

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** UX. **Severity:** P3.

- **Cause:** by design, `OrdersView.vue` `advanceActions` returns `[]` when `table_visit_id` is set; a table order completes when its visit is closed on the live board.
- **Actual:** staff on the Orders page see no action and no pointer to the live board.
- **Expected:** a short note with a link to the Live board.
- [ ] A table order on the Orders page says where it is completed. — *not started*

### XORD-050 — Dining areas are reachable only through Settings

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** UX. **Severity:** P3.

- **Actual:** the Tables page says "أنشئ منطقة جلوس أولاً" and disables Create; the sidebar has no Dining areas entry (`/admin/dining-areas` redirects to `/admin/settings/dining-areas`). Whether the hint is a link: UNVERIFIED.
- **Expected:** the hint links to the dining areas page.
- [ ] The Tables page's empty-area hint opens dining areas in one click. — *not started*

### XORD-051 — Diner menu category pill out of sync after scrolling back up

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** bug. **Severity:** P3. Seen once; not reproduced.

- **Actual:** after scrolling back to the top, "أطباق رئيسية" stayed highlighted while Drinks was on screen.
- **Expected:** the highlighted pill follows the visible category.
- [ ] Scrolling to the top highlights the first category. — *not started*

### XORD-052 — "؟T3": RTL punctuation in the table-service sheet

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** cosmetic. **Severity:** P4.

- **Actual:** "كيف نقدر نساعدك في الطاولة T3؟" renders with the question mark before T3.
- **Expected:** the Latin table label is isolated (`<bdi>` or U+2068/U+2069) so the mark stays at the end.
- [ ] The question renders "… الطاولة T3؟". — *not started; needs a person to look*

### XORD-053 — The diner's Send order button looks disabled while it is enabled

**Found:** 2026-11-06, production scenario test (`docs/testing/reports/2026-11-06-scenario-table-order-production.md`), tenant `scenario-cafe`, Claude in the built-in browser. **Type:** cosmetic. **Severity:** P4. Cause UNVERIFIED.

- **Actual:** in round 1 "إرسال الطلب" was pale although `disabled=false` and the form was valid.
- **Expected:** enabled and disabled look different.
- [ ] The enabled Send button has its full colour. — *not started; needs a person to look*

---

### XORD-045 — A till can take payment from an outdated copy of a table's check

**Found:** 2026-11-06, while fixing XORD-044. **Type:** bug (money and order integrity), found by reading, not reproduced. **Severity:** P1, proposed. **Build:** xorder-pos `c67c754` plus the uncommitted XORD-044 fix. **Status:** fixed, uncommitted (2026-11-06, owner go "Yes, fix XORD-045").

- **Module:** POS payment of a seated ticket, multi-till sites.
- **Cause (from source):** payment settles the ticket the till holds in memory and then removes the parked row by transaction id (`lib/features/payment/payment_screen.dart:209`, `OpenTicketsController.settle` in `lib/app/providers.dart`). Nothing checks that the copy being paid is the table's current version. The XORD-044 fix guards saving a check, not paying for one.
- **Steps (expected to reproduce):** till A and till B both have T3's check (same ticket). A adds a round and parks. B, before its floor refreshes (up to 5 s), opens the older copy and takes payment.
- **Actual (expected):** the order is recorded with the older lines only. A's round is never charged, and the parked row is deleted, so A's round disappears from the floor.
- **Expected:** payment is refused, with "changed on another till", when the copy is older than the table's current version; the cashier reopens the table and pays the current check.
- **Fix:** `OrdersRepository.submit` takes `tableVersion` (the version of the parked check the till pays from, `OpenTicketsController.versionOf`). `PostgresOrdersRepository.submit` locks the table's parked row (`FOR UPDATE`) before numbering or writing anything: this ticket at another version, or a parked copy that is gone → `CheckChangedElsewhere`, nothing recorded; otherwise it deletes the parked row in the same transaction, so a round parked after the payment is refused instead of being deleted unseen. A ticket never parked, and a sale on a table holding a different ticket, are not refused. Replays of a recorded sale still return it (idempotency unchanged). The payment screen puts the tender back off and says "Table T12 was changed on another till, so this payment was not recorded…" (en and ar), and refreshes the floor.
- [x] Paying an outdated copy of a seated check is refused and nothing is recorded. — *`parked_tickets_schema_test` group "paying it": "an outdated copy is refused and nothing is recorded", "a check voided or moved on another till is not paid" (both fail with the checks removed, mutation run); also "a round parked after the payment is refused, not lost", "paying the same sale again replays it", "a ticket rung up and paid without parking is not refused"; screen: `payment_check_changed_test`*
- UNVERIFIED: a payment repeated after another till already took the money for the same ticket returns the first order (the replay rule), so the second cashier is not warned that they collected twice. Not changed; a separate question.

### XORD-046 — Two tills can overwrite the same held (no-table) ticket

**Found:** 2026-11-06, while fixing XORD-044. **Type:** bug (order integrity), found by reading. **Severity:** P2, proposed. **Status:** fixed, uncommitted (2026-11-06, owner go "Yes, fix XORD-046").

- **Cause (from source):** held tickets are shown to every till on the branch, and saving one is still a plain upsert on its transaction id with no version (`lib/data/postgres/postgres_parked_tickets.dart`, `save`, the `tableId == null` branch).
- **Steps (expected):** both tills resume the same held takeaway; each adds an item and parks.
- **Actual (expected):** the second park replaces the first, and its item is lost.
- **Expected:** the same compare-and-swap as a table's check.
- **Fix:** a held save is a compare-and-swap on the row's version (migration 63's column): insert only if no held row has that transaction id (`DO NOTHING`), update only at the version the till last saw, otherwise `ParkedTicketChanged`. The till keeps a version per held ticket (`OpenTicketsController._heldVersions`, filled at boot, on refresh and on each park) and pays a held ticket with it (`submit(parkedVersion:)`, the XORD-045 guard, now also for a held row). The refusal messages have a held wording ("This held ticket was changed on another till… open it again from Held"), English and Arabic. `tableVersion` was renamed `parkedVersion`.
- [x] Two tills cannot replace each other's copy of a held ticket. — *`parked_tickets_schema_test` group "two tills on one held ticket": "both read it; the second to save an old copy is refused", "a till that never saw it cannot park over it", "a held ticket paid or voided elsewhere is not brought back"; `floor_two_tills_test`: "two tills cannot overwrite the same held ticket (XORD-046)"; the first and last fail with the version condition removed (mutation run). Paying: "paying it" under the same group (3)*

---

### XORD-044 — A second till silently overwrites a table's open check

**Found:** 2026-11-06, while planning `waiter-app` (owner: log it and fix it first). **Type:** bug (order integrity), found by reading, not reproduced. **Severity:** P1, proposed. **Build:** xorder-pos `c67c754`. **Status:** fixed, uncommitted (2026-11-06).

- **Module:** POS floor and parked tickets, multi-till sites (two or more tills on one branch PostgreSQL, either deployment mode).
- **Cause (from source):**
  - Saving a seated ticket upserts on `(restaurant_id, table_id)` and replaces `client_transaction_id` and `payload`, with no version check and no row lock (`lib/data/postgres/postgres_parked_tickets.dart:85-105`).
  - Each till loads parked tickets once at start and then works from memory; there is no NOTIFY or polling for the floor (`lib/app/providers.dart:952-1006`; `lib/domain/services/floor_overlay.dart:5-9` says multi-till consistency is not handled).
- **Steps (expected to reproduce):** till A and till B open; A seats T3, adds and sends items, parks; B (whose floor still shows T3 free) seats T3, adds an item, parks.
- **Actual:** T3's stored check is now B's ticket only; A's lines, including food sent to the kitchen, are gone from the check. Neither till is warned.
- **Expected:** B sees T3 occupied (or is refused with "this table was changed on another till") and A's check is never replaced.
- UNVERIFIED: reproduced on a real two-till site; whether any site runs two tills on one branch today.
- [x] Two tills on one database cannot replace each other's check (version or lock refuses the stale save). — *`floor_two_tills_test`: "a till whose floor still shows the table free cannot replace its check", "a stale copy of the same check cannot overwrite a newer one"; `parked_tickets_schema_test` group "two tills on one table" (4); fails with the version condition removed (mutation run, 2 tests, re-run 2026-11-06 after the simplification)*
- [x] A till sees another till's seating change without a restart. — *`floor_two_tills_test`: "another till sees a seated table without a restart" (the 5 s refresh timer, no manual call)*
- **Fix (2026-11-06, owner go "Approve, fix XORD-044"), uncommitted:** POS migration 63 adds `pos_parked_tickets.version`; the save moves it on by one (no trigger: no restaurant runs an older till, owner 2026-11-06). A seated save is a compare-and-swap: insert only if the table is free, update only at the version this till last saw, otherwise `ParkedTicketChanged`, shown as "changed on another till" with the ticket kept on screen. Clearing a table deletes another ticket's row only at a known version. Tills re-read the floor every 5 s (poll, not `NOTIFY`). Stage WS1 of `docs/features/waiter-app/TECHNICAL.md`. Not checked on two real tills by a person. Follow-ups: XORD-045 (paying an outdated copy), XORD-046 (held tickets).

---

### XORD-042 — Delete offered for a revoked POS device that has sales history

**Reported by:** the owner, 2026-11-03, while asking Claude to delete the revoked front cashier device on `demo.xorder.io/admin/settings/devices`. **Type:** UI / UX enhancement, not a data bug. **Severity:** P3.

- **Steps:** Back Office › Settings › POS devices → a revoked device that once traded → Delete → confirm.
- **Actual:** `DELETE /api/dashboard/pos/terminals/{id}` answers 422 `TERMINAL_HAS_HISTORY`; the page shows the server's message under the generic title "Something went wrong". The button is offered for every revoked device, because the device list does not say whether a device has history.
- **Expected:** the server rule stays (owner decision 2026-09-05: delete only a revoked device that never traded, `PosProvisioningService::delete`). The page offers Delete only when the server would accept it, and otherwise says the record is kept because it has sales history.
- **Environment:** production tenant `demo`, Chrome, 2026-11-03. The device was not deleted.
- **Fix (2026-11-03, owner go "Yes, log and fix"):** both terminal lists carry `has_money_history`, computed in the list query by `PosProvisioningService::withMoneyHistory` from the same predicate `delete()` uses; the pages show Delete only without history, otherwise "Kept: has money history" ("محفوظ: له سجل مالي"). Plan and evidence: `docs/features/pos-terminal-delete-visibility/`.

- [x] The dashboard list says which terminals have money history: an order, a float, a close or a count yes; an empty open shift or nothing no. — *`PosProvisioningTest::test_the_terminal_list_says_which_terminals_have_money_history`; fails with the order clause removed (mutation run)*
- [x] The flag agrees with what delete answers. — *`PosProvisioningTest::test_the_flag_agrees_with_what_delete_answers`*
- [x] The Super Admin tenant list carries the same flag with no tenant context. — *`TenantCreationTest::test_the_tenant_terminal_list_says_which_terminals_have_money_history`*
- [x] One query for the page, not one per terminal; other terminal responses keep their shape. — *`test_the_flag_costs_the_same_queries_for_one_terminal_or_many`, `test_provisioning_response_does_not_carry_the_flag`*
- [ ] Delete hidden and the kept note shown, both pages, English and Arabic; a refused delete titled "Not deleted". — *web builds; no JS tests exist; not seen in a browser*
- [ ] PostgreSQL returns the flag correctly. — *read, not run: tests are SQLite*
- **Review (2026-11-03, independent code review):** no blockers. SQL, bindings, boolean cast, tenant isolation and both templates checked. Wording changed from "sales history" to "money history", because a float or a count with no sale also keeps a terminal.
- **Risk, owner decision needed:** `orders.pos_terminal_id` has no index (foreign key only, `2026_09_02_000600_add_pos_columns_to_orders_tables.php:41`), and `pos_shifts` has no index that starts with `pos_terminal_id`. On PostgreSQL each list view may scan `orders` once per never-traded terminal. Proposed: an additive index migration (not written). Production row counts UNVERIFIED.

### XORD-043 — Terminal delete can remove a shift's cash movements

**Found:** 2026-11-03, in the review of XORD-042. **Type:** bug (money record), not investigated. **Severity:** P2, proposed.

- `PosProvisioningService::delete` treats a shift as untraded when it has no float, no close and no count. It does not look at `pos_cash_movements`.
- `pos_cash_movements.pos_shift_id` cascades on delete (`2026_09_02_000900_create_pos_shifts_and_cash_movements_tables.php:53`), and shifts cascade with their terminal (`:27`).
- So a revoked terminal whose only shift has a pay-in or pay-out, with zero float and still open, would be deleted and take those movements with it.
- UNVERIFIED: whether the POS allows a cash movement on a zero-float open shift, and whether any such row exists.
- Decision needed: count cash movements as money history (changes the delete rule, so XORD-042's flag follows automatically through `shiftTraded`), or accept it.



### XORD-038 — Identical items from later rounds print as separate receipt lines

**Reported by:** the owner, 2026-10-28 (README XORDER-008, problem B). Root cause: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section B2; plan and as-built: `docs/features/receipt-merge-rounds/`. Sent lines never merge on the ticket on purpose (the printed round and the bill must agree), and the receipt copied lines one for one. Decisions (2026-10-28): merge at presentation only; history detail, refunds and the cart keep every row; a line with a discount of its own is never merged; no round markers.

- [x] Mango Juice 1 + 1 + 2 over three rounds prints as one line, 4 for 200.00; the ticket keeps its three rows and rounds. — *`test/features/receipt_merge_test.dart` ("three rounds…", "the ticket keeps every round…"); 9 of 15 fail with the merge disabled (mutation run)*
- [x] The money figures and the sum of printed line totals are unchanged. — *same file ("the printed lines add up…")*
- [x] Not merged when the modifier, note, unit price or hand-set price differs, for a voided line, or for a line with its own discount; a same-price hand-set line merges and keeps its star. — *same file*
- [x] Same on the slip (English and Arabic) and on a reprint from the stored rows. — *same file ("the slip", "a reprint")*
- [ ] Seen on paper or the thermal-printer raster by a person. — *not seen*
- Side effects: the history detail still lists every row. A reprint cannot see a hand-set price directly; an equal unit price decides.

### XORD-041 — Dropdowns consistent (POS)

**Reported by:** the owner, 2026-10-28 (README XORDER-007). Survey and plan: `docs/features/dropdown-consistency/` (the investigation's "about 27" was a miscount: there are 10 POS dropdowns). Form dropdowns were bare Material dropdowns (underline, no frame, shorter) beside framed text fields; the filter dropdown existed in three identical copies. Decisions (2026-10-29): form dropdowns take the text-field look; the staff-row role cell stays; the web step waits until the POS result has been seen.

- [x] A form dropdown is as tall as the text field beside it, in English and Arabic. — *`test/core/pos_dropdown_field_test.dart` "is as tall as the text field beside it" (en, ar); fails with the padding forced to zero (mutation run)*
- [x] The value starts at the start edge and the arrow ends at the other, mirrored in Arabic; picking calls `onChanged`; disabled shows its hint; the inline setting is the compact frame. — *same file*
- [x] The three filter dropdowns are one widget with the same size, border and keys. — *`order_history_test`, `shift_history_panes_test`, `users_section_test` pass unchanged*
- [x] Existing dropdown call sites keep their keys and behaviour. — *`combos_ui_test` (category, option product), users and terminal tests pass unchanged*
- [ ] Looked at on screen, English and Arabic, at 1440×900 (staff editor role, combo category and option product, terminal timeout and shortcut, the three filter bars). — *not seen*
- [ ] Cloud web `<select>`s: one height for `.fld` (44 or 46), `.lib-select`/`.filter-sel` left as compact variants. — *not started; needs the owner's choice and a look*
- [ ] The staff-row role cell, narrow widths and touch. — *unchanged / not checked*
- Side effects: none on behaviour. The inline variant needed `IntrinsicWidth` (an input frame cannot have unbounded width).

### XORD-040 — Dark-mode shortcut removed from the Settings menu

**Reported by:** the owner, 2026-10-28 (README XORDER-013). Investigation: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section C; plan and as-built: `docs/features/settings-menu-no-theme-toggle/`. The row duplicated Settings › Appearance (light, dark, system). Decision (2026-10-29): remove it everywhere. Correction to the investigation: a cashier never sees this menu (XORD-030), so nobody loses their only way to change the theme.

- [x] The Settings menu has no theme row, with the till dark or light, in English and Arabic; no moon or sun icon; the other items remain. — *`test/features/settings_bar_test.dart` ("the Settings menu has no theme row when the till is dark/light", "and none in Arabic either"); all three fail with the old `app.dart` restored (mutation run)*
- [x] The theme is still chosen in Settings › Appearance. — *existing `test/features/settings_general_test.dart` "the theme offers system, light and dark…" (passes, unchanged)*
- [ ] No leftover gap or divider, RTL and LTR, seen on screen. — *not seen; by reading, no doubled divider*
- [ ] The setup wizard's later steps. — *the welcome screen keeps its own toggle; the steps after it were not checked*
- Side effects: changing the theme now needs Admin Mode (hidden chord and password) → Settings › Appearance. Labels and the `toggle` method stay because the welcome screen uses them.

### XORD-039 — `excel_export_test` fails when the date changes

**Found:** 2026-10-29 while testing XORD-038. `test/features/excel_export_test.dart` "Sales the owner's file holds every page of the filter, row for row, and the strip's four figures": expected `sales-2026-10-29.xlsx`, got `sales-2026-10-29-2026-10-28.xlsx`. Fails the same on untouched `main`. Not investigated.

### XORD-037 — Physical keyboard digits do not enter the PIN

**Reported by:** the owner, 2026-10-28 (README XORDER-012). Root cause: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section A; plan and as-built: `docs/features/pos-pin-keyboard/`. The pad only hears the keyboard while it has focus; a tap on an on-screen key left focus in the name box, so the rest of a typed PIN went into the username. Decision (2026-10-28): fix the focus handoff and add a hint; a name followed by digits still needs Enter or Tab, because a username can contain digits.

- [x] After typing a name and tapping one key, the remaining digits typed on the keyboard finish the PIN and none land in the name box. — *`test/features/sign_in_test.dart` "tapping one key hands the keyboard to the pad"; `test/features/sign_in_only_test.dart` "one tapped key hands the keyboard to the pad"; both fail with the fix removed (mutation run)*
- [x] Tab (and Enter) from the name box reach the pad, and top-row and numpad digits type; Backspace takes a digit back; letters are ignored. — *`sign_in_test.dart` (Tab + numpad, letters, existing typed-PIN and Backspace cases), `sign_in_only_test.dart` (Enter)*
- [x] The lock screen and the sign-in dialog say how to get from the name to the PIN, in English; the lock screen also in Arabic. — *`sign_in_test.dart`, `sign_in_only_test.dart` hint cases*
- [x] The supervisor-approval pad takes keyboard digits. — *existing `manager_approval_test.dart` "digits type the PIN" (not changed)*
- [ ] Tried on a real Windows and macOS keyboard, Arabic layout, touch screen. — *not tried by a person*
- [ ] Arabic hint wording read by the owner. — *wording is mine*
- Side effects: a cashier who taps one key and then types their *name* would type into the pad (letters are ignored). Admin sign-in and force-reset show no hint (they use passwords).

### XORD-036 — Order number shared by every till, restarting each trading day

**Reported by:** the owner, 2026-10-28 (README XORDER-008, problem A). Spec and plan: `docs/features/shift-order-number/` (FEATURE, TECHNICAL, DATABASE, TEST_PLAN, TEST_REPORT); investigation: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section B1. Decisions (2026-10-28): the invoice number `MAIN-2026-000001` is unchanged and stays in the database; a separate count 1, 2, 3 ... is shared by all tills of the branch, resets every business day, voided orders keep their number, and it is given at payment; offline mode first (cloud-mode branches with several tills keep one count per till until a later item).

- [x] The first order of a business day is 1, then 2, 3; the invoice number is untouched. — *`test/data/day_order_number_test.dart` (first order; invoice number as written; repository "two tills…")*
- [x] Two tills of one branch share the count, including at the same instant. — *same file ("every till…", 12 concurrent inserts)*
- [x] The next business day restarts at 1; another branch counts on its own. — *same file*
- [x] A replay returns the same number and spends none; a voided order keeps its number; no open day gives no number. — *same file, repository group*
- [x] The till role can stamp the number but cannot renumber a sale or delete counters. — *`till_grants_enforced_test.dart` new case; mutation-checked (grant removed -> `42501`)*
- [x] Old orders stay without a number after the migration; the number trigger fires after the day trigger. — *same file*
- [x] Printed on the receipt beside the invoice number (en and ar), left off when none, carried to a reprint. — *`receipt_document_test.dart` group "the order number"*
- [x] Shown in order history (`#` column, "—" when none) and in the opened order. — *`order_history_test.dart` (two new cases)*
- [ ] Cloud sync payload unchanged. — *no code change in the payload; no test pins it*
- [ ] Seen on a till, on paper (Arabic label «رقم الطلب اليومي», digits), on the sale screen after payment, at narrow widths and in RTL. — *not seen by a person*
- [ ] Cloud-mode branches with several tills share one count. — *out of scope by decision; needs the cloud to allocate it (separate item)*
- Side effects: a lost idempotency race can skip a number, as it already can for the invoice number. Every till of a branch must run the new build before migration 63 is applied. Found and fixed on the way: `pos_users_rename_test` pinned "[62]" only; the grant-list test read a comment as a table.
- The full PostgreSQL phase of `scripts/check.sh` fails on a fresh database at the committed revision (XORD-029, 507 tests); the failing set with this change is identical to the untouched revision.

### XORD-035 — One name box on every POS form, in the till's language

**Reported by:** the owner, 2026-10-27 (POS showed `Name` and `Arabic Name (Optional)` when creating a category). Root cause, decisions and plan: `docs/harness/investigations/XORD-035-pos-single-name-field.md`, `docs/features/content-languages/TECHNICAL.md`. Decisions (2026-10-27): the language is the restaurant's, stored by the wizard; the bilingual choice is removed; a stored `both` is read as the till's language; Arabic mode opens an English-only record with its English name.

- [x] Arabic: exactly one `الاسم` box, right to left, no translation box (category, default install). — *`test/features/single_name_field_test.dart` "Arabic till: one الاسم box…"; fails when the provider fix is removed (mutation run)*
- [x] English: exactly one `Name` box, left to right, no second-language box. — *same file, "English till…"*
- [x] The box and label follow the language they are written in even when the screen differs. — *same file, "chosen Arabic on an English screen" and "chosen English on an Arabic screen"*
- [x] Direction of every other small dialog, the combo and the option cells follows the language. — *`content_languages_dialogs_test.dart` (7 dialogs, new direction cases) and its option-row case; `combos_ui_test.dart` two new cases*
- [x] A stored `both` is never shown as two boxes; a stored `ar`/`en` wins over the screen. — *`test/domain/single_name_language_test.dart` (provider cases, 13 tests)*
- [x] Existing records stay accessible and lose nothing: an English-only record opens with its name; saving unchanged invents no Arabic name; renaming keeps the English one; a record with both names keeps both. — *`single_name_language_test.dart` and `single_name_field_test.dart` "records that already exist" (4); two of them fail with the pre-fill removed*
- [x] A new offline restaurant stores the wizard language; a later manager choice survives a re-run. — *`test/data/local_bootstrap_test.dart` against a real PostgreSQL (alone: 14 passed with `content_languages_test.dart`)*
- [ ] Name validation in both modes on every form. — *covered for order type (existing "the required name" cases); the other forms' required-name rules were not re-asserted*
- [ ] The wizard actually passes its language (`setup_controller.dart` `bootstrapDatabase`). — *the call is one line, analyzed, but no test drives it (needs an administrator database and the config store)*
- [ ] Every production call site reads the resolved setting. — *checked by reading (all callers use `contentLanguagesNowProvider`); no test asserts it for each form*
- [ ] Looked at in a running app (RTL alignment, labels in Arabic). — *not seen on screen*
- Side effects: older installs stored as `both` follow each terminal's language until a manager picks one; two tills in two languages can differ in that case. The extras forms use two new neutral labels. The full `scripts/check.sh` run exited 1 only from the PostgreSQL suites (see section 8.4).

### XORD-034 — Refund button shown to a cashier who cannot refund alone

**Reported by:** the owner, 2026-10-27, with a screenshot of the Orders screen (cashier signed in; Preview, Reprint and a red Refund shown). Root cause: `docs/harness/investigations/pos-refund-button-shown-to-cashier.md`. **Not fixed; awaiting a decision.**

- Finding: `order_detail_pane.dart:589` shows Refund when the decision is not `Denied`; refund is lendable, so a cashier gets `NeedsOverride` and the button is always drawn. Pressing it needs a supervisor's PIN (sheet) and the repository re-checks, so no refund happens without one. The pane's comment says "hidden", `permission_gate.dart` says "shown, with approval": the repo disagrees with itself.
- [ ] Decision: hide for roles that cannot refund alone, or keep with the approval prompt (and move it to the button press).
- [ ] Regression tests rewritten to state the rule (today `order_history_test.dart:1631` and `back_office_sales_test.dart:413` mirror the code).
- [ ] A widget test for a cashier reaching the refund sheet (none exists).
- Related: XORD-030 (top bar shown to a cashier) is the same family: controls offered to a role that cannot use them.

### XORD-033 — The open-day notice is in the status bar

**Reported by:** the owner, 2026-10-26, with a screenshot of the start screen's amber banner "يوم العمل بتاريخ 24-10-2026 ما زال مفتوحاً…": "this should be in bottom bar."
- [x] A day left open from an earlier date, and sales after a date was closed, show as a small warning in the status bar (`till-status-day-notice`), in English and Arabic, on every screen of a set-up till; the start screen no longer draws a banner for them. — *`till_status_bar_test` "a day left open… is said in the bar" (5 tests), `business_day_opening_ui_test` "the start screen carries no banner for it"*
- [x] The bar shows a short form ("Day 2026-10-24 is still open"); the full sentence is its tooltip. The full sentence said "close it from this screen", true only on the start screen, so it now says "from the start screen". — *`business_day_opening_ui_test` (both languages)*
- [x] It fits a 900 px window without overflow. — *`till_status_bar_test`*
- [ ] Looked at in the running app. — *not seen on screen*
- Side effect: the notice now also shows on the sale screen and the others, not only the start screen. Files: `lib/app/till_status_bar.dart`, `lib/features/start/start_screen.dart`, `app_strings.dart` (`dayStillOpenShort`, `dayClosedTodayShort`).

---

### XORD-032 — Sections: switch, Edit, Delete

**Reported by:** the owner, 2026-10-26, with a screenshot of the Sections page (it had Rename and "take off the rail" only): "this should have three options: Enable / Disable → should be toggle, Delete, Edit."
**Found while building it:** a section that was taken off the rail **vanished from the page** (the till's catalogue read is active-only), so it could never be put back — restore existed in the repository but nothing could reach it.
**Decision (made by Claude on the existing rule, not asked):** Delete is allowed only for a section that holds **nothing** — no item, live or archived, and no combo. `pos_products.category_id` and `pos_combos.category_id` are `ON DELETE RESTRICT` and every sale names its items, so a section that ever held one is turned off instead; the refusal says so. Its links to option groups cascade.
- [x] Each section shows a switch (on = on the till, off = hidden), an Edit button and a Delete button; the old archive icon is gone. — *`menu_sections_pane_test` "each section has three actions…"*
- [x] The switch turns an active section off and an off section back on, and a section that is off stays listed (dimmed) to be switched back on. — *`menu_sections_pane_test` "the switch is on…", "a section that is off is listed…"; PostgreSQL `postgres_catalog_admin_test` "a section that is off is listed for the switch, and not on the till"*
- [x] Delete asks first (Cancel deletes nothing); confirming deletes an empty section, audited as `category.deleted`. — *`menu_sections_pane_test` "Delete asks first…", "confirming deletes that section"; PostgreSQL "an empty section is deleted, audited, and gone"*
- [x] A section holding an item cannot be deleted, even when the item is archived, and the refusal is worded (English and Arabic); a cashier cannot delete. — *PostgreSQL "a section that holds an item cannot be deleted, even when it is off", "a cashier cannot delete a section"; widget "a section with items is refused…"*
- [ ] Looked at in the running app (Arabic and English). — *not seen on screen*
- Files: `management_menu_pane.dart` (`_CategoryList`, `_deleteCategory`), `postgres_catalog_admin_repository.dart` (`inactiveCategories`, `deleteCategory`), `admin_repositories.dart`, `catalog.dart` (`CatalogProblem.categoryHasItems`), `admin_messages.dart`, `app_strings.dart`, `providers.dart` (`inactiveCategoriesProvider`). Applies to an offline till only; on a cloud till the menu comes from the platform and the pane is not shown.

---

### XORD-031 — A table's seats are optional

**Reported by:** the owner, 2026-10-26, with a screenshot of *Add several tables*: Seats left blank showed "تتسع الطاولة لشخص واحد على الأقل" and blocked Add. "Seats should be not required."
**Decision (2026-10-26, asked and answered):** truly optional — a table with no seat count is stored with none and the floor shows none, rather than a placeholder number. The platform already allowed it (`seats_count` is nullable in the cloud schema and in its three table requests).
- [x] A blank Seats box is not a problem in the batch planner; a stated count below 1 still is. — *`table_batch_test` "a stated seat count is at least one", "seats are optional…"*
- [x] The Add several tables dialog creates ten tables with no seat count when Seats is blank, and says nothing wrong. — *`floor_bulk_tables_test` "seats left blank are allowed and sent as not stated"*
- [x] The database stores and reads back no seats, can give a table a size and take it away again, and still refuses 0. — *PostgreSQL `postgres_catalog_admin_test` "a table need not say how many it seats", "a batch with no seats stored…", "a stated count is still positive…" (54 passed in that suite)*
- [x] The cloud bootstrap's missing or non-positive `seats` now reads as "not stated" (null), not an invented 2. — *`cloud_bootstrap_test`*
- [ ] Looked at in the running app (the dialog, the floor tile with no seat count, the back-office table row). — *not seen on screen*
- **Migration 61** (`pos_dining_tables.seats DROP NOT NULL`): metadata-only in PostgreSQL, idempotent, additive; the `seats > 0` CHECK stays and passes for NULL. Exercised only on the test database `scripts/check.sh` creates; **not applied to any real branch database**. Cloud contract unchanged: `seats` may already be null in the bootstrap.
- **Side effects:** new tables now start with Seats blank (they were prefilled with 2); the cashier's floor tile shows no subtitle for a free table with no seats.
- **Found on the way, fixed here:** editing an *existing* table (the single-table form with a table that already has an id) always failed in the repository — the UPDATE was handed an unused `branch` parameter and the driver refused it. No test had ever edited a table. Fixed in `postgres_catalog_admin_repository.dart`; covered by the same PostgreSQL test (it edits a table's seats).
- Files: `lib/domain/models/dining_table.dart`, `lib/domain/services/table_batch.dart`, `lib/data/postgres/migrations.dart` (61), `postgres_catalog_admin_repository.dart`, `postgres_floor_repository.dart`, `lib/data/cloud/bootstrap_bundle.dart`, `lib/features/admin/presentation/management_floor_pane.dart`, `lib/features/floor/floor_screen.dart`.

---

### XORD-030 — The window's top bar shows Settings and the user's name to a cashier

**Reported by:** the owner, 2026-10-26, with a screenshot of the sale screen: "This cashier why it show the settings in top ?? it shouldn't appear."
**Decision (2026-10-26, asked and answered):** a cashier gets **no** window bar. It shows only in Admin Mode, for somebody holding `terminal.manage`, and while the till is being set up (the wizard's language switch). A cashier has the status bar, the sale screen's own Lock and Close shift buttons and its Orders button.
- [x] A cashier signed in sees no `MenuBar`: no Settings, no user-name menu. — *`settings_bar_test` "a cashier gets no window bar at all"*
- [x] The bar returns for a person who manages the terminal and leaves again when a cashier signs in. — *`settings_bar_test` "the bar is back when a manager of the terminal signs in…"*
- [ ] Looked at in the running app. — *not seen on screen*
- Side effects named: a cashier can no longer reach language, theme, sync now or the order history from the window bar (Orders stays on the sale screen, F7); **Reprint** is unchanged — it is the existing `receipt.reprint` permission (POS) / `pos.reprint` (platform), per role, on by default for Cashier, with supervisor approval for anyone without it. Files: `lib/app/app.dart`.

## 8. Status review — 2026-10-25

### 8.1 What "verified" means here

Ticked = an automated check that was run proves it, and the tick says which. **Nothing below was viewed in a browser or on a till by a person**, and the cloud front end has no JavaScript test setup, so every Vue screen change is "built and compiled, not exercised"; a criterion that depends only on such a screen stays unticked. **Nothing is committed or pushed.** Cloud dashboard changes are deployed to the local Docker stack (`http://admin.localhost:8080`); the POS runs as a local debug build.

### 8.2 Checks run

| Check | Result |
|---|---|
| Cloud API (`php -d memory_limit=1G vendor/bin/phpunit`) | 1115 passed. `php artisan test` runs its child at 128 MB and runs out of memory (environment limit, not a failure) |
| Cloud web, landing and menu builds (`pnpm build`) | succeed |
| POS `flutter analyze` | no issues (2026-10-25, after the XORD-022 stages 1–3 and XORD-005 dialog changes) |
| POS `flutter test` | **3170 passed, 79 skipped** (the PostgreSQL-tagged suites), 2026-10-25. A `settings_bar_test` failure in one earlier full run passed alone and did not recur; not investigated. Earlier the same day a run overlapped other sessions' edits and failed to load `postgres_catalog_admin_test.dart` (compile race, gone on re-run) |
| POS PostgreSQL suites for the work in this file (customers, order types, content languages, migrations 53, 56, 57) | passed against the fixture's own test database (content languages: not re-run in the 2026-10-25 dialog session, where `data/content_languages_test` was skipped for want of `POS_PG_HOST`) |
| POS full PostgreSQL suite | **fails (about 476 tests, a combo-option foreign-key error), identically on an untouched copy of the last commit**; `installer_owner_test` also fails there. Not caused by this work; not fixed |
| Harness (`bash scripts/harness/verify.sh`) | passes |
| XORD-015 stage 1 (2026-10-26) | cloud `php -d memory_limit=2G vendor/bin/phpunit`: **1148 passed** (1124 before; 24 new in `FinancialAccountsTest`); `pnpm build` 3 of 3; POS `flutter analyze`: no issues; POS `flutter test`: **3313 passed, 80 skipped**; PostgreSQL: `financial_accounts_test` 25 passed, and 92 passed across it, the grant-enforcement suites, `tender_types_schema_test` and `cloud_tenders_test`. Full PostgreSQL suite: `+677 -436` on a pristine copy of HEAD and `+743 -456` on the working tree, same error kinds (XORD-029). Details: `docs/features/financial-accounts/TEST_REPORT.md` |

### 8.3 Per ticket

#### XORD-001 — Select or create a customer during an order
- **Status:** Implemented, partial.
- **Existing behavior:** a search-and-add dialog existed, but only on the payment screen, with no permission on adding.
- **Files:** POS `features/payment/customer_dialog.dart`, `features/sale/widgets/cart_panel.dart`, `features/sale/sale_screen.dart`, `app/providers.dart` (`setCustomer`), `domain/models/permissions.dart` (`customers.create`), `domain/repositories/repositories.dart`, `data/postgres/postgres_customers_repository.dart`, `data/postgres/migrations.dart` (53).
- **Decisions:** choosing needs `pos.operate`; adding needs `customers.create`, checked again in the repository; a number already on file selects that person instead of overwriting their name.
- **Tests:** `order_customer_picker_test` (6), `customers_create_permission_test`, PostgreSQL `customers_repository_test`, `customers_create_migration_test`.
- **Migration 53:** gives the new key to the owner, manager, supervisor and cashier roles so nobody loses today's behaviour.
- **Remaining:** the order does not send its customer to the cloud (order payload and contract change, needs approval).
- **Cloud half built 2026-11-07** (commit `e134d9e`, on cloud `development` `c2191fb` since 2026-11-08): a till order naming this business's customer now also stores that customer's `customer_name` and `customer_phone`, which the Orders page reads; a walk-in stores neither. No contract change (the till already may send `customer_id`; `origin/main` `e9f9233` refuses another business's). Proved by `tests/Feature/Pos/PosOrdersTest.php` `test_the_order_carries_its_customers_name_and_phone_for_the_dashboard` (fails with the two lines removed, mutation run) and `test_a_walk_in_sale_has_no_customer_name_or_phone`; full cloud suite 1186 passed. - **POS half built 2026-11-07** (commit `90df643`, on POS `development` `3052a53` since 2026-11-08): `OutboxDrain` sends the customer's `platform_id` as `customer_id` (§006 field, POS-BE-014; never the local row id); a walk-in sends no key at all; a sale whose customer is still queued for upload waits a pass (`last_error` `CUSTOMER_NOT_YET_ON_PLATFORM`, deferred, not held); a sale whose customer was held for a person, or never queued, goes as a walk-in so the money is not held up. Proved by `test/data/outbox_drain_test.dart` "a sale for a customer names them by the platform id (G2)", "a sale names its customer by the platform id, a walk-in by none (G2)", "a sale waits behind a customer still on its way up, then names them (G2)", "a customer held for a person does not hold the money" (PostgreSQL); mutation runs (local id sent; wait removed) each fail them. Full `scripts/check.sh`: analyze no issues; unit pass **3539 passed, 2 skipped** (includes `outbox_drain_test`, run against PostgreSQL since `check.sh` sets `POS_PG_*`); PostgreSQL pass **1244 passed, 1 skipped**; test databases removed. **Not done:** the end-to-end check with the local cloud (both halves are uncommitted on separate branches).

#### XORD-002 — Configurable, plan-eligible order types
- **Status:** Implemented, partial.
- **Files:** cloud `Enums/TenantCapability.php` (`pos.settings.order_types.manage`), `Services/OrderTypeEntitlements.php`, `UpdateBranchRequest`, `BranchController`, `BranchResource`, `BranchForm.vue`; POS `permissions.dart`, `order_type_entitlement.dart`, `postgres_catalog_admin_repository.dart`, `management_order_types_pane.dart`, `pos_top_bar.dart`, migration 56.
- **Tests:** cloud `BranchOrderTypesTest` (13); POS `order_type_entitlement_test`, `order_types_manage_test`, `order_type_layout_test`, PostgreSQL `order_types_schema_test`, `order_types_manage_migration_test`.
- **Deviations from this spec:** stored **per branch** (the existing `supported_order_types` column), not per business; edited in the branch form and the POS Order Types pane, not "Settings → POS Configuration"; **no POS Home buttons** (the sale-screen switch adapts: one type shows a label); **no order-time check**, deliberately (a tenant whose feature flags were never set would be refused sales it has always taken), so a restricted type is blocked when saving the list, not when an order arrives; drive-thru follows the `pos` feature, which is a guess to confirm.
- **Migration 56:** gives the new key to every role and person who held `settings.manage`.
- **Cloud tills** keep a read-only pane (their types come from the platform).

#### XORD-003 — Arabic Local licence label
- **Status:** Verified. **Files:** `packages/ui/src/i18n/index.js` (5 strings), `apps/api/lang/ar/xorder.php` (1).
- **Evidence:** the runtime catalogue reads `licence.kind.offline` = لوكال, `licence.all_kinds` = سحابي ولوكال, English unchanged. The operating-mode label (`licence.mode.offline`, "غير متصل") and the API sentences about disconnected tills are intentionally unchanged. The page itself was not viewed.
- **Note:** `/pos/licences/new` is the card chooser (`ClientKindChoice.vue`), not the licence form.

#### XORD-004 — Arabic digits in phone and price fields
- **Status:** Verified, with caveats.
- **Files:** POS `core/text/digits.dart`, `core/ui/widgets/fold_digits_formatter.dart`, `core/money/{money,quantity}.dart`, five amount fields, rate fields and supplier/receipt phones; cloud `Support/Digits.php`, `Requests/Concerns/NormalizesNumericInput.php` (9 price requests), `ReceiptProfile`/`PosLicence` phone trait, two Vue phone inputs.
- **Tests:** POS `digits_test`; cloud `DigitsTest`, `ArabicDigitsInputTest` (fail without the fix).
- **Follow-up 2026-10-26:** the payment screen's authorisation / reference box was missed and stored `١١١٥…` as typed; it now folds digits (`payment_screen.dart`, test `payment_reference_digits_test`, which fails without the fold — mutation run). Other free-text boxes (order-history search, sale search, customer notes) were not audited.
- **Caveats:** supplier phone is stored as typed (an existing test records that decision); POS PIN fields still drop Arabic digits; the two Vue phone inputs rely on the existing browser-side fold and were not exercised.

#### XORD-005 — Content languages
- **Status:** Implemented. Cloud complete; POS category, item, combo, extras/size groups and seven further dialogs (2026-10-25).
- **Files:** cloud `Support/ContentLanguages.php`, `Requests/Concerns/PreservesDisabledLanguages.php`, `UpdateRestaurantProfileRequest`, `RestaurantProfileController`, `PosBootstrapService` (`bilingual`), `ProfileView.vue`, `UnitsView.vue`, 13 name checks; POS `content_languages.dart` (`resolveNames`, `hasRequiredName`, `codeFromName`), migration 57, bundle and seeder, `contentLanguagesProvider`, Settings › Language card, category/item/combo dialogs, `menu_editor_widgets.dart` (shared group editor), and the tax group, service charge, payment method, order type, unit, stock item and supplier dialogs.
- **Tests:** cloud `ContentLanguagesTest` (14; the preservation tests fail without the guard); POS `content_languages_test`, `content_languages_forms_test`, `content_languages_card_test`, **`content_languages_dialogs_test` (61; the preservation tests fail without the guard — mutation run)**, combos group in `combos_ui_test`, PostgreSQL `data/content_languages_test` (skipped without `POS_PG_HOST`). Whole POS suite `+3170 ~79` green. Feature docs: `docs/features/content-languages/`.
- **Deviations:** permission is `settings.update` (cloud) / `settings.manage` (POS), not `settings.languages.manage` (kept by owner decision 2026-10-25); the dashboard's interface language is still forced to the menu language for a single-language restaurant (now **XORD-023**); in an Arabic-only restaurant a new POS record's English column copies the Arabic name because that column is NOT NULL; a new unit or payment method with an Arabic-only name gets a generated code (`unit_…` / `method_…`).
- **Not checked:** receipts, kitchen tickets and reports reading `name_en` of a mirrored record; dialogs in a running app.

#### XORD-006 — Bulk tables
- **Status:** Implemented in the cloud and POS Back Offices.
- **Cloud:** the existing `POST /api/dashboard/tables/bulk` (max 100, all-or-nothing, 4 tests) plus a prefix, start number and quantity generator that fills an editable preview and warns about repeated names (`TablesView.vue`). The generator is not exercised by any test.
- **POS:** `TableBatch` planner (`domain/services/table_batch.dart`), `CatalogAdminRepository.createTables` (one transaction, audited per table), and an "Add several" dialog in Settings › Floor (`management_floor_pane.dart`) with a live preview. **Tests:** `table_batch_test` (9), `floor_bulk_tables_test` (10, incl. Arabic and the double press), PostgreSQL `postgres_catalog_admin_test` "adding several at once" (8).
- **Not done:** the dialog has not been looked at in the running app; the cloud generator UI is still untested.

#### XORD-007 — Bulk categories
- **Status:** Implemented in the cloud Back Office only.
- **Files:** `POST /api/dashboard/categories/bulk`, `BulkStoreCategoriesRequest`, `CategoryController::bulkStore`, `PlanLimitService`, `CategoriesView.vue`. **Tests:** `BulkCategoriesTest` (11).
- **Decisions:** all-or-nothing; up to 50 rows; the plan cap counts the whole batch; new rows append after the last. Not done: POS Back Office; the dialog is not exercised by any test.

#### XORD-008 — Permission-controlled Back Office menu entry
- **Status:** Not started.
- **Findings:** the top bar already exists but shows the back-office menus only after Admin Mode sign-in; the permission that fits is `admin.enter`. Since `origin/main` was merged, Admin Mode asks non-cashiers for a password, so "no second PIN" must be re-read against that before design.

#### XORD-009 — Edit/update licences
- **Status:** Implemented through renewal (owner decision 2026-10-25: renewing is where everything is edited and upgraded; no in-place edit).
- **Files:** `RenewLicenceRequest` (kind-aware), `LicenceIssuer` (a key sent as null clears; audit `changes`), `LicenceController::renew`, `LicenceDetails.vue` (prefilled form and a "this renewal changes" list). **Tests:** `LicenceRenewalUpgradeTest` (19). **Rule:** `.claude/rules/licences.md`.
- **Behaviour:** the client, kind and an offline customer's identifier never change; only the licence in force can be renewed (422 otherwise); the first-activation date and the key's device history carry over.
- **Remaining:** the form is not browser-tested; delivery to tills is by re-fetch under the same key, not a push; the "field allowlist" decision is now "everything the kind allows".

#### XORD-010 — Staff Management exception
- **Status:** Verified. **Root cause:** the refusal dialog's Close button asked the pane's own `BuildContext` for the Navigator, which is gone if the pane leaves the screen while the dialog is open. **Fix:** the dialog uses its own context (`management_staff_pane.dart`).
- **Tests:** `test/features/admin/staff_refusal_dialog_test.dart` (3): pane removed while the dialog is open (reproduced the exact error before the fix), plain dismiss, three rapid taps.
- **Not confirmed:** which control you tapped; any refusal dialog on that pane could raise it.

#### XORD-011 — Business-defined roles
- **Status:** Plan written, no code. **Plan:** `docs/features/tenant-roles/XORD-011-PLAN.md`.
- **Findings:** the cloud already satisfies most of it (one `Admin` role is seeded, the owner needs no role); the POS seeds Owner, Manager, Supervisor and Cashier and treats the owner as a role (11 code sites). Needs six decisions before code, starting with whether roles on cloud tills are platform-only.

#### XORD-012 — Deleted menu items remain visible
- **Status:** Not started; root cause not diagnosed.
- **Cloud findings (read-only, local Docker database):** `menu_items` and `categories` use soft deletes (rows stay with `deleted_at`); nothing in the application ever force-deletes; 10 soft-deleted categories are stored. That is the opposite of your decision that Delete removes the row. No orphan items; no live item under a soft-deleted category.

#### XORD-013 — Physically delete a category and its products
- **Status:** Not started. **Relevant:** POS `pos_products.category_id` is `ON DELETE RESTRICT` (a category with products cannot be deleted); cloud `menu_items.category_id` is `ON DELETE CASCADE`, which fires only on a physical delete the app never performs. A product belongs to one category (see XORD-014), so the shared-product question mostly applies to extras and combos.

#### XORD-014 — Product/category relationship
- **Status:** Investigated; **the reported missing relationship was not found.**
- **POS:** `pos_products.category_id → pos_categories(id) ON DELETE RESTRICT`, indexed. A later migration made it nullable with `CHECK (category_id IS NOT NULL OR is_stocked)`, so stock-only items may have no category. Combos reference a category the same way; extras attach through the junction table `pos_modifier_group_categories`.
- **Cloud:** `menu_items.category_id → categories(id) ON DELETE CASCADE`, confirmed in the migration and in the local Docker database. One-to-many (a product has one category).
- **Data audit (local Docker database only):** 0 items without a category row, 0 live items under a deleted category.
- **Cloud guards (re-verified 2026-10-25):** `StoreMenuItemRequest` and `UpdateMenuItemRequest` accept a `category_id` only if the category belongs to the caller's restaurant **and is not soft-deleted**. `Rule::exists` does not skip soft-deleted rows; that was the one real gap (an item parked under a deleted category would vanish from the dashboard and the POS bundle). Tests: `CategoryAndItemTest::test_an_item_cannot_be_created_in_or_moved_to_a_deleted_category`, `TenantIsolationTest::test_item_cannot_be_attached_to_another_restaurants_category`. Category delete (single and bulk) soft-deletes its items in one transaction; the menu import resolves categories through the tenant scope.
- **Sync (cloud side), tested:** `PosCatalogRelationTest` (3): every bundle item names a category in the bundle; deleting a category removes it and its items from the bundle together; the bundle carries no other restaurant's rows. The POS seeder (`bootstrap_seeder.dart`) replaces the catalog wholesale on a full sync and silently skips a product whose category is missing (read, not run).
- **POS guard added 2026-10-25:** `PostgresCatalogAdminRepository.saveProduct` wrote `category_id` with no check. It now refuses (`CatalogProblem.categoryUnavailable`, EN/AR wording) a category that is not this restaurant's, or that is archived when the item is new or moving into it; repricing an item already in a since-archived category stays allowed. Files: `catalog.dart`, `postgres_catalog_admin_repository.dart` (`_categoryUnavailable`), `admin_messages.dart`, `app_strings.dart`. Tests: `postgres_catalog_admin_test.dart` group "the category an item sits in" (3). **These 3 have NOT been run:** they are `integration`-tagged and need `POS_PG_HOST`.
- **Remaining gap, needs approval (schema change, so not done):** neither database ties `restaurant_id` on the product to `restaurant_id` on its category. The foreign key covers only `category_id`, so the database alone would accept a cross-tenant pair; only request validation prevents it. A composite foreign key `(category_id, restaurant_id)` needs a unique key on `(id, restaurant_id)` of the category table first. **UNVERIFIED:** whether any row on the real POS or production database already violates it (only the local Docker cloud database was audited).
- **Not done:** the POS database was not inspected live; POS category/product delete and the POS sync of deletions were not tested; no constraints or migrations were changed; the POS menu import was not reviewed for the same category check.

#### XORD-015 — Payment methods linked to financial accounts
- **Status:** **Stage 1 implemented 2026-10-26** (accounts, branch link, default account per payment method and branch); not committed, not deployed. Stage 2 (account on each payment and refund, cashier override, admin transfers, movements and balances) not started and not approved. Root cause of the gap and the plan: `docs/harness/investigations/XORD-015-financial-accounts-missing.md`, `docs/features/financial-accounts/`.
- **Files:** cloud migrations `2026_10_26_000100/000200`, `FinancialAccount`, `TenderAccountDefault`, `FinancialAccountController`, `TenderAccountDefaultController`, requests, `TenantCapability::FINANCE_ACCOUNTS`, `PosBootstrapService` (`money.financial_accounts`, `money.tender_account_defaults`), `PosConfigVersion`; web `FinancialAccountsPanel.vue`, `PaymentMethodsView.vue`; POS migration 60, grants, `financial_account.dart`, both Postgres repositories, `BootstrapSeeder`, `ManagementAccountsPane` (Finance › Accounts), `PosCapability.financeAccounts`. Contract `POS-BE-032` **PROPOSED**.
- **Tests (run):** cloud `FinancialAccountsTest` 24; POS `financial_accounts_test` (PostgreSQL) 25, `financial_accounts_bundle_test` 10, `domain/financial_accounts_test` 17, `management_accounts_pane_test` 15, grant probes in `till_grants_test`, `till_grants_enforced_test`, `admin_grants_enforced_test`. Whole-suite results are in `docs/features/financial-accounts/TEST_REPORT.md`.
- **Deviations from the finding:** the permission is `finance.accounts` (owner only by default; not `settings.update`), because whoever may rename a payment method must not be able to redirect the money; defaults are per branch with a business-wide fallback (owner decision 2026-10-26); the cashier override and transfers the owner asked for need recorded movements and so are stage 2. **Arabic wording is my proposal and needs your read.**
- **Not done / not seen:** the dashboard Accounts tab was built (`pnpm build` green) but **not opened in a running browser**; the Finance › Accounts pane was widget-tested but **not looked at on a running till**; no old POS build was run against the new bundle (argued by reading); not committed or pushed.

#### XORD-021 — Business logo
- **Status:** Implemented; automated tests pass, UI not looked at in a running app, whole chain not run against a real cloud.
- **Files (cloud):** `app/Services/PosConfigVersion.php` (logo/brand-colour bump), `tests/Feature/Pos/PosBrandingVersionTest.php`. **Files (POS):** migrations 58–59; `domain/models/business_logo.dart` (validation), `postgres_business_logo_repository.dart`, `data/cloud/logo_sync.dart`, `bootstrap_bundle.dart`/`bootstrap_seeder.dart`/`cloud_sync.dart`, `businessLogoProvider`, `business_logo_card.dart` (Settings › General), `StartLogo` on the start screen, capability `business.branding.manage`, EN/AR strings.
- **Tests:** cloud `PosBrandingVersionTest` (6); POS `BusinessLogoRules` unit tests (21) and PostgreSQL `test/data/business_logo_test.dart` (needs `POS_PG_HOST`). Acceptance criteria and evidence: section 2.
- **2026-10-26, discoverability:** the card sat under the whole company form in Settings › General and was not found on a till. It now opens the page: `ManagementReceiptPane` takes a `leading` list, `management_screen.dart` passes `BusinessLogoCard` there. Tests: `back_office_shell_test` "General opens with the business logo…" (fails with the card back under the form, mutation-checked) and `receipt_profile_ui_test` (leading above the form, sections below). `flutter analyze` clean; `flutter test` +3178 ~79 passed. **Still not seen in the running app** (a hot restart is needed).

#### XORD-022 — Back Office navigation restructuring
- **Status:** Stages 1–3 implemented 2026-10-25 (labels, moves, merge, account menu); stages 4 (dropdown design and keyboard) and 5 (permission gates) not started. Filed as "XORD-018", renumbered because 018 was taken. Full write-up, inventory and mapping: `docs/features/back-office-navigation/NAVIGATION_INVENTORY.md`.
- **Where it lives:** the bar is `app.dart` `_settingsBar` (`menu_bar` package); tabs, 46 panes, labels and gates are `management_screen.dart` (`BackOfficeTab`, `ManagementPane`, `_paneRequires`, `managementBarFor`). Back Office pages are not URL routes (one `/management` route, the pane travels in `extra`), so "preserve routes" means keeping the `ManagementPane` names, `/management` and `/orders`.
- **Reported problems checked against source:** confirmed — Payment methods in **three** places (Reports, Finance, Settings; only Settings manages them, the other two read the same report); "Orders & invoices" (→ order history) next to "Orders & invoices settings"; the same history screen reachable from Sales and Settings; Dining areas under Menu; Customers inside People; Switch user inside Settings; language and theme toggles beside their panes (deliberate: reachable without Admin Mode). Only a naming collision — Employees (Reports) vs Staff (People). Not a content overlap — System vs Settings. **UNVERIFIED:** dropdown width, active state, RTL placement and keyboard behaviour (not seen running).
- **Finding that changes the plan:** the current ten-tab structure is the owner's own map (14–15 Sep 2026, cited in the code) and the proposal is that map with a few renames, `floor` moved out of Menu, and a new account menu. Three proposed items have **no destination today** (Stocktaking, Financial Accounts, Reports › Inventory) and "Business Settings" is ambiguous; none should be built to fill a menu. The proposed "Finance → Payment Methods: manage" does not match the code: Finance is read-only by design.
- **Permissions (022-F):** most of it exists (`admin.enter` door, `_paneRequires`, empty tabs hidden, deep links refused, owner retained); **21 panes have no gate beyond the door**. The repositories already enforce `catalog.manage`, `staff.manage`, `settings.manage`, `pos.settings.order_types.manage` and `business.branding.manage`, which could gate those panes; the pane-by-pane trace is not done. No manager or custom-role navigation test exists.
- **Baseline:** `flutter test test/features/back_office_shell_test.dart test/features/settings_bar_test.dart` → 61 passed. Both files pin the current map and Arabic labels and will need deliberate edits.
- **Implemented (POS only; no cloud, migration or contract change):** `app_strings.dart` (Dashboard, Management, Order history, Employees, Products, Dining areas & tables, Account; Arabic لوحة التحكم، الإدارة، الموظفون والعملاء، قائمة الطعام، المنتجات، الصالات والطاولات، الحساب), `management_screen.dart` (new `BackOfficeTab.account`; `floor` to Management; `financePayments` removed; `user`/`about` out of Settings), `management_finance_panes.dart` (`PaymentLedgerSection`), `report_breakdown_panes.dart` (ledger under Reports › Payment methods), `app.dart` (account menu replaces the Log out button and the Switch user and About lines of Settings). **Arabic wording is my proposal and needs your read.**
- **Tests:** edited `back_office_shell_test`, `settings_bar_test`, `admin_entry_test`, `cloud_purchasing_hidden_test`, `finance_panes_test`; new `back_office_shell_test` "every pane has a label…". Results in 8.2. **Not seen on screen** (no screenshots yet).
- **Next step:** your reading of the Arabic words; decisions on Sales / order history, then stages 4 and 5.
- **Dependencies:** XORD-008 (Admin Mode and `admin.enter`), XORD-011 (roles; "Roles & Permissions" and custom-role tests), XORD-015 (Financial Accounts, Settlements), XORD-005 (language setting that 022-D must make canonical).

#### XORD-024 / 025 / 026 — Receipt logo, alignment, currency
- **Status:** Implemented 2026-10-26, POS only (no cloud, migration or contract change). Description, plan, test plan and report: `docs/features/receipt-logo-and-layout/`.
- **Checks:** `flutter analyze` clean; whole POS suite `+3269 ~79` passed (2026-10-26, final run after review fixes). New: `receipt_amounts_test` (18), `logo_bitmap_test` (6), `receipt_logo_raster_test` (11), `receipt_logo_provider_test` (5), plus additions to `receipt_document_test`, `receipt_print_test`, `printer_settings_test`; `reprint_test` updated for the currency code. Seven mutation checks, all caught (list in TEST_REPORT.md).
- **Found on the way:** the preview wrapped the currency code under the figure (theme letter spacing not in the measurement) and the printer form would have reset any new setting on the next edit; both fixed and pinned by tests.
- **Not done / not proved:** a real print on 80 mm and 58 mm; the real-font width of the 190-dot price column; the running app (needs a hot restart). Format-only churn in `receipt_printing.dart`, `reprint_dialog.dart`, `receipt_dialog.dart` was left because the sandbox declined `git checkout` to revert it.

#### XORD-027 — VAT 0 still charged at 14%
- **Status:** Implemented 2026-10-26, POS only, offline tills (no cloud, migration, schema or contract change). Plan and as-built: `docs/features/tax-rules/TECHNICAL.md`.
- **Files:** POS `data/postgres/postgres_catalog_admin_repository.dart` (`saveMoneyConfig` also sets the default group's rate in the same transaction; over-100% refused; audit carries the group's rate), `features/admin/presentation/management_taxes_pane.dart` (box seeded from the default group; groups re-read after save), `features/sale/widgets/cart_panel.dart` (VAT label from the applied rate via `receiptPercent`). Edits are mixed with other uncommitted work in the same three files.
- **Tests:** new — six PostgreSQL tests in `postgres_catalog_admin_test`, three in `money_panes_ownership_test`, three in `tax_groups_wiring_test`, three in `cart_totals_alignment_test`. Mutation-checked: the old seeding, the old label, a no-op UPDATE and the removed invalidation each make a test fail.
- **Not done:** repairing tills that already disagree; the stale "VAT 14%" line on the setup review screen (`setup_panes.dart:1778`, `vatValue`); the service row's label (`toStringAsFixed(0)`, same rounding of fractions); a running-app or on-paper check.

#### XORD-042 — Delete offered for a revoked device with sales history
- **Status:** Implemented 2026-11-03, uncommitted. Details and ticks in section 7.
- **Files:** cloud `app/Services/PosProvisioningService.php`, `Http/Controllers/Dashboard/PosTerminalController.php`, `Http/Controllers/Admin/RestaurantTerminalController.php`, `Http/Resources/PosTerminalResource.php`, `apps/web/src/pages/dashboard/PosTerminalsView.vue`, `apps/web/src/pages/admin/RestaurantDetails.vue`, `packages/ui/src/i18n/index.js` (three keys, en and ar).
- **Tests:** 4 new in `PosProvisioningTest`, 1 in `TenantCreationTest`. Full suite: 1189 of 1191 pass; the 2 failures are the untracked `GuestPagingTest`, unrelated.
- **Not done:** browser check of both pages; PostgreSQL run.

#### XORD-016 to XORD-020
Described under section 2.
- **016, 017:** cloud `pos_licence_activations` table (migration `2026_10_25_000100`, additive), `LicenceActivator::activate`, `GET` and `DELETE …/activations`, POS `LicenceSeatsFull`. Tests: `LicenceActivationsTest` (23), `offline_licence_activation_test`; re-run 2026-10-25 (cloud licence group 111, POS licence tests 35 passing).
- **017 verified, with caveats:** the Release button is not browser-tested; the owner decision on counting cloud devices is still open; the platform trusts the device id the till reports (a locked `fingerprints` list is the stronger control); a till built before this change shows a generic refusal.
- **018:** `LicenceDetails.vue` (one style rule; visual check pending).
- **019, 020:** POS `MonoCode` alignment, `order_history_screen.dart`, `history_widgets.dart`, `order_detail_pane.dart`; tests in `order_history_test.dart` (10, run against the original code to confirm they fail there).

#### XORD-044 — A second till silently overwrites a table's open check
- **Status:** Implemented 2026-11-06, uncommitted. Both boxes ticked in section 7.
- **Files:** POS `lib/data/postgres/migrations.dart` (63), `lib/data/postgres/postgres_parked_tickets.dart`, `lib/app/providers.dart` (`OpenTicketsController`, `ParkOutcome`), `lib/app/router.dart`, `lib/features/sale/sale_screen.dart`, `lib/core/l10n/app_strings.dart` (`tableChangedElsewhere`, en and ar); tests `test/data/floor_two_tills_test.dart` (new, 3), `test/data/parked_tickets_schema_test.dart` (4 new, 1 rewritten: it asserted the overwrite), `test/features/open_tickets_test.dart` (2 new).
- **Checks run:** `flutter analyze` no issues; `scripts/check.sh` unit pass **3539 passed, 2 skipped**; the two parked-ticket PostgreSQL suites alone **18 passed**, and **17 passed** after the simplification (the older-till test removed; analyze clean, `open_tickets_test` + `park_ticket_test` 20 passed); full PostgreSQL pass **698 passed, 514 failed**, the shared-database cleanup failures of XORD-029 (`pos_staff` missing, foreign keys blocking `DELETE FROM pos_restaurants`); `parked_tickets_schema_test` fails there at its setup for the same reason, `floor_two_tills_test` passes there. No pristine-HEAD baseline re-run today. Test databases dropped (3 of 3).
- **Not done:** XORD-045, XORD-046; a person checking two real tills; `NOTIFY`-driven refresh.

#### XORD-045 — A till can take payment from an outdated copy of a table's check
- **Status:** Implemented 2026-11-06, uncommitted. Box ticked in section 7.
- **Files:** POS `lib/domain/repositories/repositories.dart` (`submit(tableVersion:)`, `CheckChangedElsewhere`), `lib/data/postgres/postgres_orders_repository.dart` (`_takeParkedCheck`), `lib/data/cloud/outbox_drain.dart` and `lib/data/eta/filing_orders_repository.dart` (pass it on), `lib/data/fakes/fake_repositories.dart`, `lib/data/unconfigured/unconfigured_repositories.dart`, `lib/app/providers.dart` (`versionOf`), `lib/features/payment/payment_screen.dart`, `lib/core/l10n/app_strings.dart` (`paymentCheckChanged`); tests `test/data/parked_tickets_schema_test.dart` (6 in "paying it"; setup now truncates orders first), `test/features/payment_check_changed_test.dart` (new), `test/data/filing_orders_test.dart` (signature).
- **Checks run:** `flutter analyze` no issues; parked-ticket PostgreSQL suites 23 passed; mutation run 2 failures as expected; `payment_check_changed_test` 1 passed. Full `scripts/check.sh` (2026-11-06, after XORD-044 and XORD-045): analyze no issues; unit pass **3540 passed, 2 skipped**; PostgreSQL pass **721 passed, 496 failed**, all in other suites (the XORD-029 shared-database failures; 698/514 before this change). `parked_tickets_schema_test` now passes in the full run too, because its setup truncates orders first; `floor_two_tills_test` passes. Test databases dropped (3 of 3).
- **No schema change.** No cloud contract change (the outbox payload is untouched).

#### XORD-046 — Two tills can overwrite the same held ticket
- **Status:** Implemented 2026-11-06, uncommitted. Box ticked in section 7.
- **Files:** POS `lib/data/postgres/postgres_parked_tickets.dart` (held compare-and-swap, `ParkedFloor.heldVersions`, `ParkedTicketChanged.tableId` nullable), `lib/data/postgres/postgres_orders_repository.dart` (held row in `_takeParkedCheck`), `lib/domain/repositories/repositories.dart` (`CheckChangedElsewhere.tableId` nullable, `parkedVersion`), `lib/app/providers.dart`, `lib/core/l10n/app_strings.dart` (held wording), callers in `router.dart`, `sale_screen.dart`, `payment_screen.dart`; tests `parked_tickets_schema_test.dart` (6 new, 1 updated to pass its version), `floor_two_tills_test.dart` (1 new).
- **Checks run:** `flutter analyze` no issues; `flutter test test/features` 1919 passed; parked-ticket PostgreSQL suites 30 passed; mutation run 2 failures as expected. Full `scripts/check.sh` (finished 2026-11-07; the Mac slept mid-run, so its clock reads 185 min): analyze no issues; unit pass **3540 passed, 2 skipped**; PostgreSQL pass **719 passed, 505 failed**, none in `parked_tickets_schema_test`, `floor_two_tills_test`, `filing_orders_test` or the payment and parking suites; the failures are the XORD-029 shared-database ones (721/496 on the previous run; the count moves between runs). Test databases dropped (3 of 3).
- **No schema change** beyond migration 63. No cloud contract change.
- **Follow-up fixed 2026-11-07:** voiding uses the same guard: `voidOrder(parkedVersion:)` checks and lets go of the parked row in the void's transaction (an outdated copy → `CheckChangedElsewhere`, nothing recorded, "changed on another till" toast), and clearing a ticket without an order (`settle` → `remove`) deletes its row only at the version this till holds. Tests: `parked_tickets_schema_test` "voiding the current check records it and lets the table go", "voiding an outdated copy is refused and nothing is recorded" (both fail with the guard removed, mutation run), "clearing an outdated copy leaves the newer check". 71 PostgreSQL tests across the parked, two-till, integration, filing and tax-line suites passed; `flutter test test/features` 1919 passed.

#### XORD-047 — Diner prices trusted from the phone
- **Status:** fixed on cloud branch `fix/xord-047-server-priced-diner-orders` (`6e27fcd`), not pushed. Boxes ticked in section 7.
- **Files:** `apps/api/app/Services/DinerOrderPricing.php` (new), `Http/Controllers/Public/PublicOrderController.php`, `Http/Requests/Public/StoreOrderRequest.php`, `Http/Resources/Public/{MenuItem,Combo}PublicResource.php`, `lang/{en,ar}/xorder.php`; `apps/menu/src/{App.vue,components/OrderSuccessModal.vue,composables/useCart.js,composables/useLocale.js}`; tests `tests/Feature/DinerOrderPricingTest.php` (new), `tests/Concerns/BuildsDinerOrders.php` (new), 9 order suites updated.
- **Checks:** full cloud suite 1157 passed; menu build succeeds; no browser check.

#### XORD-048 — Order details do not show the table (widened: the sheet matches the receipt)
- **Status:** committed `c2191fb`, merged into cloud `development` (fast-forward) 2026-11-08, not pushed. Two of three boxes ticked in section 7. Full suite re-run on `c2191fb`: 1186 passed; web build succeeds.
- **Files:** `apps/api/routes/api.php` (`GET dashboard/orders/{order}`, under `can:orders.read`), `Http/Controllers/Dashboard/OrderController.php` (`show`; the list loads `table:id,label`), `Http/Resources/OrderResource.php` (`table_label`; the receipt fields only when `payments` is loaded), `Models/Order.php` (`posTerminal()`), `apps/web/src/pages/dashboard/OrdersView.vue` (sheet fetches details on open; table on the row), `packages/ui/src/i18n/index.js` (`orders.sheet_*`, en + ar), `tests/Feature/Pos/OrderReceiptSheetTest.php` (new).
- **Checks:** `OrderReceiptSheetTest` 5 passed; the order suites 45 passed; full cloud suite **1184 passed** (throwaway `APP_KEY`); `pnpm --filter @xorder/web build` succeeds; browser check against a stubbed API only. **Not done:** a real API in the browser (the local Docker stack runs other code); PostgreSQL (tests are SQLite); tender names are stored in one language, so the payment line shows the name as typed.

#### XORD-058 — A cloud till prints its own invoice number (follow-up)
- **Status:** first fix `db3c2cd`; follow-up `9f3d850`; both on POS `development` (`3052a53`), not pushed. Boxes ticked in section 7.
- **Files:** POS `lib/domain/repositories/repositories.dart` (`OrdersRepository.platformInvoiceNumber`), `lib/data/postgres/postgres_orders_repository.dart`, pass-throughs in `outbox_drain.dart` and `filing_orders_repository.dart`, `fake_repositories.dart`, `unconfigured_repositories.dart`; `lib/app/providers.dart` (`salesDeliveredProvider`, bumped in `applySyncOutcome`); `lib/features/receipt/{receipt_data,receipt_dialog}.dart` (`ReceiptData.numbered`, dialog re-reads); `lib/domain/models/order_record.dart` (`platformNumbered`, `shownInvoice`), `lib/data/postgres/postgres_order_history_repository.dart` (column), `lib/features/history/presentation/{order_history_screen,order_detail_pane}.dart`; tests `test/features/receipt_platform_number_test.dart` (new), `test/data/provisional_invoice_test.dart` (3 new), `test/features/order_history_test.dart` (2 new), `test/data/filing_orders_test.dart` (signature).
- **Checks:** `flutter analyze` no issues; `receipt_platform_number_test` 3 passed; `provisional_invoice_test` 6 passed (PostgreSQL); `order_history_test` 68 passed; three mutation runs each failed as expected. Full `scripts/check.sh` on the branch: analyze clean, unit 3540 passed, PostgreSQL 1247 passed; and on the merge with G2 (`3052a53`): unit 3544 passed, 2 skipped, PostgreSQL 1247 passed, 1 skipped, "All checks passed", test database dropped.
- **No schema change, no contract change.** Not checked by a person on a real till.

### 8.4 Not yet in the project

- **Nothing is committed or pushed.** A push to `xorder-cloud` `main` deploys to production and needs `/release-check` first; that working tree also holds about 87 unrelated restyle files.
- **Feature documentation:** written for `content-languages` (`docs/features/content-languages/`, state `drafted`). Not updated (`/project-documentation update`) for the other affected features. The harness has a rule (`.claude/rules/licences.md`) and a memory for the licence decisions.
- **Migrations to review before any real deployment:** cloud `2026_10_25_000100_create_pos_licence_activations_table`; POS 53, 56, 57, 58, 59, 63. All additive (58 adds nullable columns and two CHECK constraints on a table of one row per restaurant; 59 appends one capability to the `owner` role). The local Docker database has had the cloud one applied.
- **Open decisions:**
  - XORD-002: drive-thru entitlement; order-time check.
  - XORD-005: receipts and kitchen tickets for mirrored Arabic names; the form-refresh criterion.
  - XORD-008: second PIN against the new Admin Mode password.
  - XORD-011: six questions.
  - XORD-013: shared products.
  - XORD-015: override policy.
  - XORD-017: cloud device counting.
  - XORD-022: approve the menu hierarchy after the mapping; which proposed destinations do not exist yet.
  - XORD-023: interface language decoupling (per user or per restaurant).

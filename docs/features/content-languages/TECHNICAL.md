# Technical: Content languages (XORD-005)

Verified against: 2026-10-25 · cloud `main 06bc8e3` + uncommitted · POS `main 2e7e612` + uncommitted.

## POS design (this session's stages)
- `lib/domain/models/content_languages.dart`: `ContentLanguages` (`arabic|english|both`, `showsArabic/showsEnglish`), `resolveNames` (what a save writes), **new** `hasRequiredName` (the required name is the one the form shows) and `codeFromName` (code with a non-Latin fallback).
- Dialogs take `languages` (default `both`, so every existing caller and test is unchanged) and callers pass `ref.read(contentLanguagesNowProvider)`: `tax_group_dialog`, `service_charge_dialog`, `tender_type_dialog`, `order_type_dialog`, `unit_dialog`, `stock_item_dialog`, `supplier_dialog`, and the Extras pane's `_ExtraDialog`.
- Shared group editor `menu_editor_widgets.dart`: `EditableOption`/`EditableGroup` remember the names as stored; `EditableGroup.toDraft(s, languages:)` resolves group names, menu headings and option names; `OptionRows(languages:)` draws only the enabled cells. The item editor's inline groups (`management_menu_pane.dart`) use the same.
- Keys added for testing: `tender-name`, `tender-name-ar`, `charge-name`, `charge-name-ar`.

## Decisions
- Both mode keeps today's behaviour exactly (raw text passed through in the group editor).
- Mirroring (BR-4) is chosen over making `name_en` nullable: no migration, no reader changes.
- No schema, no contract and no cloud change in this stage. Rollback = revert the dialog files.

## Not done
See FEATURE.md "Known limits".

---

## XORD-035 — one name box, in the till's language (AS BUILT · 2026-10-27, uncommitted)

Specification: `docs/harness/investigations/XORD-035-pos-single-name-field.md`. Plan verified against POS `8d80eb1` (clean for the files below; unrelated dirty files: `refund_sheet.dart`, `open_item_dialog.dart` and their tests, not mine). Root cause re-confirmed: `seedRestaurant` (`local_bootstrap.dart:352-366`) still inserts without `content_languages`, so a fresh install is `both` (`migrations.dart:4586-4603`); the wizard's locale is never written to it; the commit after the report touched none of this.

**Acceptance criteria (from the ticket):**
AC-1 Arabic: exactly one `الاسم` box, RTL, right-aligned. AC-2 English: exactly one `Name` box, LTR, left-aligned. AC-3 no second-language box on any form. AC-4 name validation works in both. AC-5 create and edit behave the same. AC-6 existing records stay reachable, nothing lost. AC-7 applies to category, item, combo, extras/size groups, unit, tax group, service charge, tender type, order type, stock item, supplier.

**Design (Option A + runtime fallback; defaults pending approval, see Open decisions):**
1. *One chokepoint.* Every production caller of these forms passes `ref.read(contentLanguagesNowProvider)` (`providers.dart:1396`). It stops ever returning `both`: `both` (stored, loading, no database, cloud `bilingual`) resolves to the terminal's language (`localeProvider`). So every form on every existing install shows one box with **no data write and no migration**. The enum value and the wire/bundle value `both` stay (contract unchanged).
2. *New installs store the choice.* Offline setup passes the wizard language into `seedRestaurant(contentLanguages:)`; the insert writes it only on a new row, the existing `ON CONFLICT … DO UPDATE SET slug = slug` leaves a re-run row alone. The value is then the restaurant's, shared by every till on the branch server.
3. *Direction and label follow the language the box is written in.* `MenuInput`/`_OptionField` take an explicit direction (English was `null` = "inherit the screen", the defect in report 3(c)); the single label comes from the content language's own strings (`ArStrings().fieldName` = `الاسم`, `EnStrings().fieldName` = `Name`), via a small helper on `ContentLanguages`. When screen and content language agree (the normal case) nothing looks different from the screen's other labels.
4. *Existing records.* `resolveNames` is unchanged (never blanks the hidden name; `name_en` stays NOT NULL). New: in Arabic mode a record with no Arabic name opens with its English name in the box instead of empty (`initialArabicName`), because most pre-existing rows have only `name_en` (English was the first, required field). Saving writes the box to the active language's column and keeps the other.
5. *Appearance card* offers Arabic / English only (the bilingual choice goes); hint text updated. The stored value `both` is still read, shown as the language it resolves to.

**Stages** (POS only; each ends with its tests; rollback = revert that stage's files, no data to undo):
| # | Change | Files | Proves it |
|---|---|---|---|
| 1 | `ContentLanguages.resolvedFor(languageCode)`, `fromLocale`, `initialArabicName`, label/direction helper; `contentLanguagesNowProvider` resolves `both` by locale | `lib/domain/models/content_languages.dart`, `lib/app/providers.dart` | unit tests in `test/domain/` (new file, next to `content_languages` tests); provider test |
| 2 | `seedRestaurant({contentLanguages})`; setup passes `ContentLanguages.fromLocale(state.locale)` | `lib/data/postgres/local_bootstrap.dart`, `lib/features/setup/application/setup_controller.dart:804` | PostgreSQL-tagged test (`test/data/`): new row = `ar`/`en`, re-run keeps a manager's later choice; runs only under `scripts/check.sh` |
| 3 | Direction + single label + Arabic prefill in the 12 forms | `menu_editor_widgets.dart` (MenuInput, OptionRows), `management_menu_pane.dart` (category, item), `management_combos_pane.dart`, `management_extras_pane.dart`, `unit_dialog`, `tax_group_dialog`, `service_charge_dialog`, `tender_type_dialog`, `order_type_dialog`, `stock_item_dialog`, `supplier_dialog` | extend `content_languages_dialogs_test.dart` and `content_languages_forms_test.dart`: one box, label text, `textDirection`, validation, create/edit parity, record-with-both-names edited in each mode |
| 4 | Appearance card: two choices | `management_appearance_pane.dart`, `app_strings.dart` hint (both languages) | update `content_languages_card_test.dart` |
| 5 | Default-install test: provider not overridden, wizard-created restaurant → every form shows one box | new widget test | the regression that would have caught this |

Tests that change meaning: `content_languages_forms_test.dart` "both: two fields" and the card test's third choice now assert the new behaviour; dialogs constructed directly with `ContentLanguages.both` (default parameter) still draw two boxes and are left as characterisation of the widget, not of the till.

**Verification:** `cd apps/xorder-pos && flutter analyze && flutter test test/features/content_languages_*.dart test/features/combos_ui_test.dart test/features/units_pane_test.dart test/core/localisation_test.dart`, then the full `flutter test`, then `scripts/check.sh` for stage 2 (needs local PostgreSQL; reported as NOT RUN if unavailable). Cannot be proved by tests: how it looks on screen (RTL alignment on a real Windows/macOS build); closest proof is the `textDirection`/label assertions.

**Impact:** no cloud change, no contract change, no schema, no migration, no data rewrite, nothing reaches `xorder-cloud` `main`. Cloud tills (bundle `bilingual: true`) never author these forms (`management_menu_pane.dart:28`; repositories refuse when `!offline`) so they are unaffected. Venues: café and food truck (one till, one language) gain most; a restaurant with two tills in two languages is the risk — a *new* install is fixed by the stored value, a *legacy* install on `both` follows each terminal's language until a manager picks one in Appearance.

**Decisions taken 2026-10-27 (owner, via the plan questions):** D1 per restaurant, stored at setup; D2 first answered "keep the bilingual choice", which contradicts D3 (a stored `both` cannot be both "not chosen yet" and "chosen"), then resolved to **remove it**; D3 runtime fallback to the terminal language, no data write; D4 pre-fill the English name in Arabic mode; D5 (default taken, not asked) the label is in the box's own language.

**As built — deviations from the plan above:**
- The direction/label helper is its own file, `lib/features/admin/presentation/content_language_ui.dart` (`ContentLanguagesUi.nameDirection/nameStrings`, `NameDirection` wrapper), not part of `menu_editor_widgets.dart`, so the small dialogs do not import the whole editor-widgets file. The wrapper is a `Directionality` around label and box together; `MenuInput` and the private `_Field` classes were not changed.
- `resolveNames` gained one rule (BR-8): an unchanged English stand-in is not saved as an Arabic name.
- `EditableOption.from` / `EditableGroup.from` / `_GroupState` take `languages` so option, group and combo-group names pre-fill too. Menu headings (`displayAr`) are not pre-filled (optional; empty means "use the group name").
- Extras library: two neutral labels replace "(English)/(Arabic)" in single mode (`extrasLibraryName`, `extrasMenuName`, both languages).
- Dialogs still accept `ContentLanguages.both` and draw two boxes (default parameter, kept as characterisation); no production caller passes it, because every caller reads `contentLanguagesNowProvider`. Checked by reading the call sites listed in the plan.
- Tests that assumed two boxes on a default till were rewritten (item, category, combo, unit pane).

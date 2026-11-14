# Feature specification: Content languages (XORD-005)

Status: implemented. Cloud complete (earlier work, re-run only); POS category, item, combo, extras/size groups and the eight small dialogs (this session).
Slug: `content-languages` · Module: `menu-management` (also touches `pricing-tax-tenders`, `restaurant-and-branches`) · Footprint: shared (the platform flag travels to the till in the bootstrap bundle)
Verified against: 2026-10-25 · cloud `main 06bc8e3` + uncommitted work · POS `main 2e7e612` + uncommitted work. Core state: `drafted`. Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `W:` = `apps/xorder-cloud/apps/web/`, `P:` = `apps/xorder-pos/`.
Not re-audited this session: the cloud request classes and the two Vue pages (only `ContentLanguages.php` was read and the 14-test file run). Treat cloud details below as the tracker's account (`docs/qa/XORDER_QA_FINDINGS.md`, XORD-005), **UNVERIFIED** against source today.

## Summary
A restaurant chooses which languages its **content** (names and descriptions of categories, items, combos, extras, tax groups, tenders, order types, units, stock items, suppliers) is written in: Arabic only, English only, or both. Forms ask only for the enabled languages. A language switched off is hidden, never deleted: a save keeps the stored value, and switching it back on shows the original.

This is content, not the interface: the till's or dashboard's own language is the user's choice and is read nowhere here.

## Business rules
- **BR-1** Three settings. Cloud: `restaurants.bilingual` + `default_language` (`bilingual=false, default=ar` = Arabic only; `=en` = English only; `bilingual=true` = both). POS: `pos_restaurants.content_languages` in `ar|en|both` (`P:lib/data/postgres/migrations.dart:4586-4600`). Mapping: `ContentLanguages.fromPlatform` (`P:lib/domain/models/content_languages.dart`). `C:app/Support/ContentLanguages.php`.
- **BR-2** Only the enabled language is required. Both: English stays required in the POS dialogs (unchanged behaviour); the cloud accepts either one.
- **BR-3** A hidden language is never overwritten: the POS `resolveNames` keeps the stored value; the cloud `PreservesDisabledLanguages` does the same.
- **BR-4** `name_en` is NOT NULL in every POS table involved, so in an Arabic-only restaurant the English column **mirrors the Arabic name** on create, and on edit only while it was still a mirror. A real English translation is never overwritten. Switching English on later shows that Arabic text, ready to translate.
- **BR-5** A machine code made from a name (units, payment methods) cannot come from Arabic; `codeFromName` falls back to `unit_<stamp>` / `method_<stamp>`, still editable on create.
- **BR-6** Unknown or missing setting means `both` (stored value). In the POS `both` is **never shown as two boxes** (XORD-035, supersedes the earlier "safe way to be wrong"): see BR-7.
- **BR-7** (XORD-035, POS) The POS writes names in **one** language. The form's language is the restaurant's stored `ar`/`en` when it made that choice, otherwise (`both`, loading, no database) the till's own language (`localeProvider`), via `ContentLanguages.resolvedFor`. The offline setup wizard stores its chosen language as the restaurant's setting when it creates the restaurant row. The box label, direction and alignment are those of the box's own language (`الاسم`/RTL, `Name`/LTR), whatever the screen shows. Settings > Appearance offers Arabic only or English only; the bilingual choice is gone (decision 2026-10-27).
- **BR-8** (XORD-035) An Arabic-only form opens an older record that has no Arabic name with its English name in the box (`initialArabicName`); saving it unchanged keeps the English name and writes **no** Arabic name; renaming writes the Arabic name and keeps the English one.

## Where it applies
| Surface | State |
| --- | --- |
| Cloud API (13 name checks, update guard, bootstrap `bilingual`) and dashboard Profile/Units pages | implemented; tracker says cloud forms not browser-tested |
| POS category and item dialogs | implemented, tested (earlier) |
| POS combos (name, group names) | implemented; tests added 2026-10-25 |
| POS extras library and the item editor's inline groups (group names, menu headings, option names) | implemented 2026-10-25 via `EditableGroup.toDraft(languages:)` and `OptionRows(languages:)` |
| POS tax groups, service charges, payment methods, order types, units, stock items, suppliers | implemented 2026-10-25 |
| POS settings > Language card | implemented (earlier); XORD-035: Arabic / English only |
| POS single name box on every form above (XORD-035) | implemented 2026-10-27: provider resolves `both`; wizard stores the language; label, direction and Arabic pre-fill follow BR-7/BR-8 |

## Venue-model fit
Helps Arabic-only cafés, food trucks and cloud kitchens, which are the likely single-language venues; a one-language owner no longer sees a second empty box on every form. No dependence on tables, addresses or connectivity.

## Known limits and deviations
- Permission is `settings.update` (cloud) and `settings.manage` (POS), not the proposed `settings.languages.manage` (owner decision 2026-10-25: keep).
- The dashboard's interface language is still forced to the menu language for a single-language restaurant (existing behaviour; contradicts "keep interface language separate"). Logged as XORD-023.
- POS Back Office screens that are not name forms (receipts, kitchen tickets, reports) were **not** checked for reading `name_en` of a mirrored Arabic item. UNVERIFIED.
- Dialogs were exercised in widget tests only, not in a running app.
- XORD-035: cloud tills still receive `bilingual: true` as `both`; they never author these forms, so nothing changes for them. A restaurant with two tills in two languages and the stored value `both` (an install made before XORD-035) follows each terminal's language until a manager picks one in Appearance. The wizard-to-setting link (`setup_controller.dart` `bootstrapDatabase`) is not exercised by any test (needs an administrator database and the config store); the database half is (`local_bootstrap_test.dart`).

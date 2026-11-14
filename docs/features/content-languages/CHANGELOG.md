# Changelog: Content languages (XORD-005)

- 2026-10-27 (POS, uncommitted; XORD-035): one name box on every form. `contentLanguagesNowProvider` resolves `both` to the till language; `seedRestaurant(contentLanguages:)` stores the wizard language on a new restaurant; label, direction and Arabic pre-fill follow the box's language (new `content_language_ui.dart`, `initialArabicName`); Appearance card drops the bilingual choice; two neutral extras labels added (`extrasLibraryName`, `extrasMenuName`). No schema, contract or cloud change.
- 2026-10-25 (POS, uncommitted): tax groups, service charges, payment methods, order types, units, stock items, suppliers and extras/size groups (incl. inline item groups) follow the content-language setting; `hasRequiredName`, `codeFromName`; combos covered by tests.
- Earlier (uncommitted): cloud rules and guard, bootstrap flag, POS category/item dialogs, Language card, migration 57.

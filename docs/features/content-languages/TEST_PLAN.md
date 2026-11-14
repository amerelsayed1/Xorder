# Test plan: Content languages (XORD-005)

| Criterion | Test |
| --- | --- |
| Three combinations render the right fields: tax group, order type, unit, payment method, service charge, stock item, supplier | `test/features/content_languages_dialogs_test.dart` (per dialog, 3 modes) |
| Combos, three combinations | `test/features/combos_ui_test.dart` "content languages (XORD-005)" |
| Extras / sizes / inline groups: option cells follow the setting | `content_languages_dialogs_test.dart` "extras and sizes" |
| Hidden language survives a save (English only; Arabic only with a real translation) | same, every dialog + group editor |
| Arabic-only create mirrors English; required name is the visible one | same, "the required name" |
| Codes from Arabic-only names | same, "a code made from a name" |
| Category, item, setting card, mapping | existing `content_languages_*` tests |
| Cloud rules | `apps/xorder-cloud/apps/api/tests/Feature/ContentLanguagesTest.php` (14) |
| PostgreSQL round trip of the setting | `test/data/content_languages_test.dart` (needs `POS_PG_HOST`) |

| XORD-035: provider never returns `both`; stored choice wins; loading is not `both` | `test/domain/single_name_language_test.dart` |
| XORD-035: Arabic-only record with only an English name opens with it; save invents no Arabic name; rename keeps English | same file; `test/features/single_name_field_test.dart` "records that already exist" |
| XORD-035: default install shows exactly one box, correct label and direction, Arabic and English screens; stored-language-differs-from-screen cases | `test/features/single_name_field_test.dart` |
| XORD-035: every small dialog, combo and option cell run in their own direction; Arabic pre-fill | `content_languages_dialogs_test.dart`, `combos_ui_test.dart` |
| XORD-035: new restaurant stores the wizard language; re-run keeps a later choice (PostgreSQL) | `test/data/local_bootstrap_test.dart` (needs `POS_PG_HOST`) |

Gaps: the wizard call that passes its language (`bootstrapDatabase`); item/extras editor labels in a running app; two tills in two languages; receipts/kitchen tickets with mirrored names; cloud forms in a browser; every dialog in a running app; Arabic RTL layout of the single-field dialogs.

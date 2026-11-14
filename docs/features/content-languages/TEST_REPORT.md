# Test report: Content languages (XORD-005)

Date: 2026-10-25 · macOS, Flutter/Dart 3.13.5, PHP SQLite in-memory · cloud `06bc8e3` + uncommitted · POS `2e7e612` + uncommitted.

| Command | Result |
| --- | --- |
| `cd apps/xorder-cloud/apps/api && php artisan test --filter ContentLanguages` | `passed 14, assertions 49` (before the POS stage; cloud untouched since) |
| `cd apps/xorder-pos && flutter analyze` | `No issues found!` (after the POS stage) |
| `flutter test test/features/content_languages_dialogs_test.dart` | `+61: All tests passed!` |
| mutation: `resolveNames` English-only branch changed to return `nameAr: ''`, same file | `+53 -8: Some tests failed` (7 dialogs + shared group editor); change reverted |
| `flutter test test/features/combos_ui_test.dart` | `+24: All tests passed!` (3 new) |
| `flutter test` (whole POS suite) | `+3170 ~79: All tests passed!` |

Notes
- An earlier full run (before the final changes) had one failure, `settings_bar_test.dart` "a line opens its page, and Log out leaves Admin Mode ... (macOS)"; it passed alone (`+24: All tests passed!`) and did not recur in the final full run. It is outside this feature (file already modified in the working tree): treated as order/timing dependent, **not investigated**.
- Skipped (~79): PostgreSQL-tagged suites incl. `test/data/content_languages_test.dart` (`POS_PG_HOST` not set). **Not run.** `scripts/check.sh` **not run**.
- Not run: any cloud test beyond `ContentLanguages`; `pnpm build`; any running-app or browser check.

---

## XORD-035 (2026-10-27) · macOS, Flutter 3.47.7 · POS `c67c754` + `test/data/local_bootstrap_test.dart` uncommitted · PostgreSQL local, one run per file

| Command | Result |
| --- | --- |
| `dart analyze lib` (after the changes) | `No issues found!` |
| `flutter test test/features/content_languages_forms_test.dart test/features/content_languages_dialogs_test.dart test/features/content_languages_card_test.dart test/features/combos_ui_test.dart test/features/units_pane_test.dart test/core/localisation_test.dart` | `+110` then `All tests passed!` after six assertions that assumed two boxes were rewritten; first run `+107 -6` |
| `flutter test test/domain/single_name_language_test.dart` (new, 13) and `test/features/single_name_field_test.dart` (new, 8) | all passed |
| mutation 1: provider's `.resolvedFor(...)` removed | 9 new tests failed (`+12 -9`); reverted |
| mutation 2: `initialArabicName` returns `''` | 2 new tests failed; reverted |
| `scripts/check.sh` (analyze, then widget/unit, then PostgreSQL) | analyze clean; widget/unit **`+3530 ~2: All tests passed!`**; PostgreSQL stage **`+689 ~1 -514`**, `EXIT=1` |
| `flutter test --tags integration --concurrency=1 test/data/content_languages_test.dart test/data/local_bootstrap_test.dart` | `+14: All tests passed!` (includes the new XORD-035 seed test) |

The PostgreSQL stage failures are one family: foreign-key violations while suites clear shared tables (`pos_combo_options_product_id_fkey` 145, `pos_orders_voided_by_fkey` 126, `pos_orders_business_day_fk` 22, others fewer), the same signature the tracker records as XORD-029 (about 436–456 failures on an untouched copy, 2026-10-26). 514 is higher than that figure; **I did not run a pristine copy of this commit, so "no worse than before" is not shown**, only that the errors are of that kind and untouched by this change. `content_languages_test.dart` failed inside that run for the same reason and passes alone.
Not run: the cloud suites (no cloud change); any running-app or on-screen check; the wizard's call into `seedRestaurant`. Test databases of this checkout were dropped with `tool/drop_test_databases.dart` after listing them with `--dry-run`.

# PIN entry from the physical keyboard — test report
Date 2026-10-28 · Branch `fix/pos-pin-keyboard` (off `main` `c67c754`), uncommitted · one unrelated uncommitted file `test/data/local_bootstrap_test.dart` carried along, not touched · Flutter 3.47.7, macOS. No database involved.

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` (whole suite, no PostgreSQL) | **3535 passed, 82 skipped (PostgreSQL-tagged), 0 failed** |
| `flutter test test/features/sign_in_test.dart` | 25 passed (6 new) |
| `flutter test test/features/sign_in_only_test.dart` | 13 passed (3 new) |
| Mutation: the `requestFocus` line removed | `tapping one key hands the keyboard to the pad` fails (lock screen) and `one tapped key hands the keyboard to the pad` fails (shift dialog); file restored |

New tests: tap one key then keyboard digits finish the PIN with none in the name box (lock screen, sign-in dialog); Tab from the name box then numpad digits; letters ignored once the pad has focus; Enter in the name box moves to the pad (dialog); the hint in English and Arabic (lock screen) and English (dialog). Already covered before: typed PIN and Backspace (`sign_in_test.dart`), keyboard PIN in the supervisor dialog (`manager_approval_test.dart`).

**Not proven / gaps:** the real Windows and macOS keyboards, Arabic keyboard layouts (the test sends logical keys), and touch were not tried by a person; the Arabic hint wording is mine; the lock screen when no name tile fits (more than six people) not looked at on screen; a user who types a name and then digits **without** Enter or Tab still types them into the name box, by design (usernames may contain digits); the hint is the mitigation. The PostgreSQL suites were not run (nothing in them is touched).

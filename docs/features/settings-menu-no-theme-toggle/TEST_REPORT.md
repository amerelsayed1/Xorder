# Remove the dark-mode shortcut from the Settings menu — test report
Date 2026-10-29 · Branch `fix/settings-no-theme-toggle` (off `main` `c67c754`), uncommitted · one unrelated uncommitted file `test/data/local_bootstrap_test.dart` carried along, not touched · Flutter 3.47.7, macOS. No database involved.

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test test/features/settings_bar_test.dart test/features/settings_general_test.dart` | all passed (settings_bar: 3 new cases replace 1) |
| Mutation: the old `app.dart` put back (change stashed) | the 3 new cases fail (dark, light, Arabic); change restored afterwards, stash empty |
| `flutter test` (whole suite, no PostgreSQL) | 3528 passed, 82 skipped (PostgreSQL-tagged), **1 failed: `excel_export_test.dart`** (date-dependent, fails identically on untouched `main`, XORD-039) |

New tests prove: with the till dark or light, and in Arabic, the Settings menu has no "Switch to light/dark" text and no moon or sun icon, while Order history and the language item are still there. Already covered and unchanged: `settings_general_test.dart` "the theme offers system, light and dark, and each is the…" (Appearance still sets the theme); the language item flip.

**Not proven / gaps:** the menu was not looked at on screen (no stray divider checked by eye; by reading, the language item is followed by the existing `if (managesTerminal) MenuDivider()`); the setup wizard steps after the welcome screen were not checked for a theme switch; `brightnessProvider.toggle` is still used by the welcome screen, so no dead code was left.

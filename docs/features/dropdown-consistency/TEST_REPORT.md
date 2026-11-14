# Consistent dropdowns (POS) — test report
Date 2026-10-29 · Branch `fix/dropdown-consistency` (off `main` `c67c754`), uncommitted · one unrelated uncommitted file `test/data/local_bootstrap_test.dart` carried along, not touched · Flutter 3.47.7, macOS. No database involved.

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test test/core/pos_dropdown_field_test.dart` | 7 passed (all new) |
| Mutation: the frame's padding forced to zero | the two "as tall as the text field" cases (en, ar) fail; restored |
| History, shift-history, users and filter suites after the refactor | all passed (105 in the first four files) |
| `flutter test` (whole suite, no PostgreSQL) | 3533 passed, 82 skipped (PostgreSQL-tagged), **1 failed: `excel_export_test.dart`** (date-dependent; fails identically on untouched `main`, XORD-039) |

New tests prove: `PosDropdownField` is as tall as the `TextField` beside it (48 px) in English and Arabic; in LTR the value starts at the left edge and the arrow ends at the right, mirrored in RTL; picking an item calls `onChanged`; with no `onChanged` it shows its disabled hint and does not open; the compact inline variant is narrower than the form width and shorter than 48 px. The existing history, shift-history, users, combos and terminal tests (which find the dropdowns by the same keys) still pass.

**Not proven / gaps:** nothing was looked at on screen; there are no golden images, so pixel-level padding is unproven beyond the height and edge checks; the table-cell role dropdown and the web `<select>`s were not changed; midway I restored `pos_widgets.dart` from `main` by mistake and had to re-add the two new widgets from my own text, so every number above comes from the re-added final file (diff: 139 lines added, 0 removed).

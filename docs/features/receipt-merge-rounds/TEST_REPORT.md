# Receipt: identical items from several rounds — test report
Date 2026-10-29 · Branch `fix/receipt-merge-rounds` (off `main` `c67c754`), uncommitted · one unrelated uncommitted file `test/data/local_bootstrap_test.dart` carried along, not touched · Flutter 3.47.7, macOS. No database involved.

| Command | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test test/features/receipt_merge_test.dart` | 15 passed (all new) |
| Mutation: `consolidate` returns its input | 9 of the 15 fail (6 pass because they assert lines stay apart); restored |
| `flutter test` (whole suite, no PostgreSQL) | 3541 passed, 82 skipped (PostgreSQL-tagged), **1 failed: `excel_export_test.dart` "Sales the owner's file holds every page of the filter…"** |
| The same test on untouched `main` (my changes stashed) | **fails identically**: expected `sales-2026-10-29.xlsx`, got `sales-2026-10-29-2026-10-28.xlsx`. It depends on today's date (the day rolled over); not caused by this change (filed as XORD-039, not investigated) |

New tests prove: three rounds of the same juice (1 + 1 + 2) print as one line, 4 for 200.00; the ticket keeps its three rows and rounds; printed line totals and the engine's subtotal are unchanged; order of first appearance; different modifier, note, unit price, repriced state, a voided line and a line carrying a discount of its own all stay apart; the same hand-set price merges and keeps its star; a line with no key is kept; the slip shows one `Mango Juice` row, 4, 200.00 in English and Arabic; a reprint from stored rows merges the same way and keeps apart a different key, price, note, void or line discount.

**Not proven / gaps:** the printed paper and the thermal-printer raster were not looked at by a person (the raster tests still pass); a reprint cannot see a hand-set price directly (equal unit price decides); the order history detail, refunds and the cart deliberately still show every row; the kitchen has no print in the code; no PostgreSQL suite was run (nothing in them is touched).

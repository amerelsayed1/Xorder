# Test report — receipt-logo-and-layout

Run 2026-10-26 on macOS, Flutter (stable), `apps/xorder-pos` at `a6f5fe5` plus the uncommitted working tree. Real output below; nothing here is a claim about a command that was not run.

## Commands and results
| Command | Result |
|---|---|
| `flutter analyze` | `No issues found!` |
| `flutter test test/features/receipt_amounts_test.dart` | `+18: All tests passed!` |
| `flutter test test/features/logo_bitmap_test.dart` | `+6: All tests passed!` |
| `flutter test test/features/receipt_logo_raster_test.dart` | `+11: All tests passed!` |
| `flutter test test/features/receipt_logo_provider_test.dart test/features/printer_settings_test.dart` | `+13: All tests passed!` |
| `flutter test test/features/receipt_print_test.dart` | `+20: All tests passed!` |
| `flutter test test/features/receipt_document_test.dart` | `+22: All tests passed!` |
| `flutter test test/features/receipt_document_test.dart test/features/reprint_test.dart` | `+46: All tests passed!` |
| `flutter test` (whole POS suite) | `+3249 ~79: All tests passed!` (the 79 skipped are the PostgreSQL-tagged suites; **not run**, they need `POS_PG_HOST` and nothing here touches the database) |
Baseline before this change, same day: `+3178 ~79`. The difference includes tests from other sessions' work in the same tree, so it is not all this change.

## Existing tests changed on purpose
`receipt_document_test` (17 figure assertions now end in ` EGP`; the split-bill, VAT, discount, subtotal and paid rows, and item prices) and `reprint_test` ("prints the totals that were charged": `175.00 EGP`, `17.50 EGP`, `26.95 EGP`). `receipt_document_test`'s exhaustive block switch gained `SlipLogo`. No other existing assertion changed.

## Mutation checks (change reverted, then restored)
| Put back | Tests that failed |
|---|---|
| Amounts pinned at natural width, left-aligned in Arabic | "amount rows … end at the same dot in Arabic" (80 and 58 mm) |
| Code under the total centred | "the currency under the total ends where the figure ends" (Arabic, English) |
| Preview without the shared amount box | "the preview amounts end together, in ar" |
| Item prices left-aligned in Arabic | "the items column ends at one dot in Arabic" |
| Plain threshold instead of dither | `logo_bitmap_test` (4), "a light-coloured logo still prints", "only black and white dots" |
| Form rebuilds the config from name and paper | "survives choosing a printer and a paper width afterwards" |
| Switch ignored by `receiptLogoProvider` | `receipt_logo_provider_test` "none when this till is set to leave it off", `receipt_print_test` "and not when…", "the preview shows none…" |
The first run of the items-column test did **not** fail under its mutation: in the test font every glyph is a full em wide, so long prices overflowed the column and looked aligned. The test was rewritten with shorter figures and then failed correctly. A first version of the preview test found a real bug (below).

## Defect found by the tests and fixed
The preview measured an amount with the plain mono style, but a `Text` also inherits the theme's default style (letter spacing), so the text was wider than its box and the currency code wrapped under the figure. The measurement now uses the same default style and text scale as the `Text`.

## Not run, not proved
- **A real thermal printer** (AC-4): logo legibility, 80 mm and 58 mm, Arabic and English. The tests prove ink is present, sized and placed; they do not prove it looks good.
- **The running app.** The preview and print paths were exercised in widget tests only. A hot restart of the running debug app is needed before the owner can see it.
- **Fonts.** `flutter test` draws text in the test font (square glyphs), not IBM Plex or the Arabic face, so widths in the tests are not the widths on paper. The 190-dot price column is sized by arithmetic (about 14 characters at 13 dots) and must be looked at on paper.
- **AC-6b** (queued job unchanged after the logo changes) and **AC-10b** (change line carries the code) have no test of their own; see TEST_PLAN.md.
- PostgreSQL-tagged suites (79 skipped).

## Update after review (2026-10-26)
Review fixes added tests: price column fits the widest price (raster, Arabic and English; preview), a real logo in the preview is above the name and at print scale, and the QR test compares every dot under the logo with the slip without one. Each of those was put against the old behaviour and failed there.
`flutter analyze` and the full suite were re-run after the fixes. At that point the working tree also held **another session's in-progress till status bar** (`lib/app/till_status_bar.dart`, `lib/app/app.dart`, `test/features/back_office_shell_test.dart`), which made `flutter analyze` report two errors (`BackOfficeConnectionPill` undefined in `back_office_shell_test.dart`) and made `admin_entry_test.dart` and others fail. Those are not in files this change touches. See the result below.

**Final run, 2026-10-26, after the review fixes and after the other session's status bar settled:** `flutter analyze` → `No issues found!`; `flutter test` (whole POS suite) → `+3269 ~79: All tests passed!`. The 79 skipped are the PostgreSQL-tagged suites (not run). The earlier failures and analyzer errors seen mid-run were that other session's unfinished edits and did not recur.

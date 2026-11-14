# Test report — receipt-design-system
Run 2026-10-26 · macOS (Darwin 25.6.0) · Flutter, no database, no printer · xorder-pos `a6f5fe5` + a large uncommitted working tree (XORD-024/025/026 receipt work and others, not this feature's alone).

| Command | Result |
|---|---|
| Baseline before any edit: `flutter test` on the 8 receipt files (`receipt_document`, `receipt_amounts`, `receipt_raster`, `receipt_print`, `receipt_logo_raster`, `receipt_logo_provider`, `receipt_profile_ui`, `reprint`) | `+138: All tests passed!` |
| After the build, same 8 files | `+138: All tests passed!` (one structure test edited, see below) |
| New: `flutter test test/features/receipt_design_test.dart` | `+16: All tests passed!` |
| Mutation: two-line limit put back in both renderers' item path | 6 of the new tests failed (both widths, Arabic, and the preview at 328 and 220 px); restored, `+16` pass |
| `flutter analyze` (whole project) | `No issues found!` |
| Full `flutter test` | `+3329 ~81: All tests passed!` (before this feature the last full run was `+3269 ~79`) |
| Preview generator: `RECEIPT_PREVIEW_DIR=… flutter test test/tool/receipt_previews_test.dart` | wrote 10 PNGs to `previews/before/` (before any edit) and 10 to `previews/after/` |

The two extra skipped tests are the preview generator (skipped unless the env var is set) and one other skip that is not from this feature; I did not trace it.

## Matrix
| AC | Result |
|---|---|
| AC-1 | pass (`receipt_design_test` "the structure") |
| AC-2 | pass on the paper at 384 and 576 dots (Latin and Arabic) and in the preview at 328 and 220 px; mutation-checked |
| AC-3 | pass |
| AC-4 | pass as a proxy: size and margins blank for a six-figure total and a split bill; **not** a look at it |
| AC-5 | pass |
| AC-6 | covered by existing XORD-024 tests and previews 3, 4, 9; no new assertion |
| AC-7 | existing amount/currency tests pass unmodified; previews 1–5 looked at |
| AC-8 | money, tax, discount and payment tests pass unmodified |
| AC-9 | done: `previews/` and `BEFORE_AFTER.md` |
| AC-10 | **not done: needs a person with a 58 mm and an 80 mm printer** |

## What was edited on purpose
`test/features/receipt_document_test.dart`: the `SlipOrnament` case removed from a switch, and the test "nothing above the ornament names it…" now finds the footer by the thank-you line. Nothing else existing was modified.

## Gaps and caveats
- Validation is on the **document and the bitmap**, not paper. Margins, thermal contrast and heads that drift need a real 58 mm and 80 mm printer.
- The in-app preview dialog was tested as a widget; I did not open it in the running till.
- Preview case 8's sample figures are not arithmetically consistent (see `BEFORE_AFTER.md`); it compares layout only.
- No golden-image tests, by the owner's decision.
- Modifiers, add-ons, variants, per-line discounts, notes and unit price are **not** shown, because the receipt model has none (decision C-3); that is not a defect of this change.

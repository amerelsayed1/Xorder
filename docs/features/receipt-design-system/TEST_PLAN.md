# Test plan — receipt-design-system
Planned 2026-10-26. Executed results in `TEST_REPORT.md`. Flutter tests in `apps/xorder-pos/test/features/` and `test/tool/`; no cloud, database or printer.

| AC | Proof | Test |
|---|---|---|
| AC-1 sections in order, stable rule pattern | rules are solid, dashed, heavy in that order; heavy directly above the grand total; section order title → facts → items → money → total → payment → footer text → `xorder.io` | `receipt_design_test` "the structure" |
| AC-2 long item names print whole on 58 and 80 mm | a longer name makes a taller slip with no stop at two lines (Latin and Arabic, both widths); in the preview no line limit, no ellipsis, name/quantity/price rectangles do not overlap at 328 and 220 px | `receipt_design_test` "item names are never cut" (mutation-checked) |
| AC-3 rules | the three above; thickness unchanged (`SlipMetrics.ruleThickness`) | "the structure" |
| AC-4 grand total | 44 dots, larger than the title, the label and twice the body; a six-figure total and a split bill leave the head's margins blank on 58 and 80 mm | "the grand total", "nothing runs into the margins" |
| AC-5 footer | thanks once in both languages, no look-forward line; tenant text printed above it; an empty note adds nothing; `xorder.io` last | "the footer" |
| AC-6 header | logo, name wrap and no-logo cases are covered by the existing XORD-024 tests and by previews 3, 4, 9; no new assertion | existing tests + previews |
| AC-7 Arabic / English / mixed | the order of values is unchanged; amount and currency tests pass unmodified; previews 1–5 | `receipt_amounts_test`, `receipt_document_test` + previews |
| AC-8 no calculation change | the money, tax, discount and payment tests pass unmodified; only a structure test that named the old ornament was edited | existing suites |
| AC-9 previews | nine cases, before and after | `previews/` + `BEFORE_AFTER.md` |
| AC-10 real printers | **needs a person**: 58 and 80 mm output, thermal contrast, margins | manual |

Edited on purpose: `receipt_document_test` (the footer's start is now the thank-you, not the ornament; `SlipOrnament` no longer exists).
Needs a person: a printed slip on 58 mm and on 80 mm; a look at the in-app preview dialog in both languages.

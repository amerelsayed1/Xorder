# Changelog — receipt-design-system

## 2026-10-26 — built (xorder-pos, uncommitted)
- `slip_style.dart`: spacing scale `spaceXs/Sm/Md/Lg/Section`; role names `businessTitle`, `sectionHeading`, `bodyPrimary`, `bodySecondary`, `itemName`, `numericValue`, `grandTotal`, `footerText`; `itemGap`; title 38 → 34, total amount 56 → 44, total label 34 → 30; rule gaps now `spaceSm`. Ornament tokens and the heart glyph removed.
- `receipt_document.dart`: three rules instead of six (space replaces the rest); metadata rows carry `secondary: true`; `SlipGap.medium()` and `SlipGap.section()`; the "we look forward" line and `SlipOrnament` removed from the footer; `SlipRow.secondary` added. No `data.*` value, label or format changed.
- `receipt_raster.dart` and `receipt_paper.dart`: item names, row labels, row values and the total label wrap fully (the two-line limit with an ellipsis is gone); label and value on one baseline; quieter label when `secondary`; items spaced by `itemGap`; ornament drawing removed.
- Tests: new `receipt_design_test.dart` (16); `receipt_document_test.dart` edited where it named the ornament. New `test/tool/receipt_previews_test.dart` (writes pictures only when `RECEIPT_PREVIEW_DIR` is set; skipped otherwise).
- Behavior to know about: a queued or reprinted slip prints in the new layout; the slip is shorter on most sales and longer when an item name is long.

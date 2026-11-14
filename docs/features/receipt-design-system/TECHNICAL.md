# Technical plan — receipt-design-system
Status: **built 2026-10-26 (owner: "go on")** · 2026-10-26 · Spec: `FEATURE.md` · Repo: `apps/xorder-pos` only · Source: `a6f5fe5` + uncommitted tree (XORD-024/025/026 receipt work is part of it)

## Deliverable 1 — current implementation (verified)
- **Technology:** Flutter `dart:ui` only. `ReceiptDocument.of(...)` → `List<SlipBlock>`; `ReceiptRaster` paints those blocks to a bitmap in dots and a 1-bit raster goes to the printer (`receipt_raster.dart`); `ReceiptPaper` draws the same blocks as widgets for the preview/dialog (`receipt_paper.dart`). A re-queued job is re-rendered from the document, headless.
- **Widths:** `PrinterConfig.width80mm = 576`, `width58mm = 384` printable dots; `SlipMetrics` is written for 80 mm and everything scales for 58 mm; margin 12 dots each side.
- **Tokens that exist:** `SlipMetrics` (type sizes, columns `qty 64` / `price 190` widened to fit and capped at 45 %, gaps, rule thicknesses, logo 120 dots). **Not tokens yet:** a named spacing scale, named type roles, and which blocks get which rule.
- **Styling limitations found:** item names `maxLines: 2` with ellipsis (`receipt_raster.dart:562,571`); six rules in a normal slip (after header, before items, dashed before money, heavy above total, after total, after payments); grand total 56 dots against 22 body; labels and values in metadata rows are the same size; footer = tenant note + thanks + look-forward + heart + `xorder.io`.
- **Reusable already:** the block types (`SlipCentre`, `SlipLogo`, `SlipRow`, `SlipItemsHeader`, `SlipItem`, `SlipGrandTotal`, `SlipRule`, `SlipGap`), `SlipMetrics`, `paintSlipGlyph`, the 22+13+9+20 block/raster tests.
- **Printer risks:** monochrome 1-bit threshold (text 50 %, logo has its own), drift at the head's outer columns (hence the margin), queued jobs change appearance after the update, no real-printer access here.

## Deliverable 2 — plan
**Principle:** change `SlipMetrics`, the block list and the two renderers; add no field to `ReceiptData`/`ReceiptLine`; leave every `data.*` value and its formatting as it is.

| Stage | Change | Proof | Rollback |
|---|---|---|---|
| 0 | Baseline `flutter test` on the receipt tests; add a preview generator (a test that only writes files when `RECEIPT_PREVIEW_DIR` is set) and render the **before** PNGs of the nine cases (ar/en × 58/80, mixed, many items, long names, discounts and taxes, no logo) into `docs/features/receipt-design-system/previews/before/` | PNGs and the baseline output | delete the generator |
| 1 | **Tokens** in `slip_style.dart`: a named spacing scale (`spaceXs…spaceSection`) replacing the loose gaps; named type roles mapped onto the existing sizes (`BusinessTitle`, `SectionHeading`, `BodyPrimary`, `BodySecondary`, `ItemName`, `NumericValue`, `GrandTotal`, `FooterText`); grand-total amount 56 → 44; a label size smaller than the value size | existing receipt tests still green (sizes are not asserted by value; checked) | revert the file |
| 2 | **Document** (`receipt_document.dart`): rules cut from six to three plus the shaded items header (after the branding; dashed before the summary; heavy above the total), with gaps replacing the rest; the footer's look-forward line and heart ornament dropped (D-2); nothing else removed | `receipt_document_test` updated where it asserts the old rule or footer structure, with each change listed; a test that every figure and label of the old slip is still present | revert the file |
| 3 | **Items** (both renderers): names wrap fully, no `maxLines`, quantity and price columns untouched; row gap per token; header wraps instead of clipping | new tests with 120-character Arabic, English and mixed names on 58 and 80 mm, measuring that no name, quantity or price rectangles overlap and that no ellipsis is produced | revert the two renderers' item paths |
| 4 | **Rows and total** (both renderers): metadata labels in the secondary size, values in the body size, same alignment rules as today (BR-8); grand total label and amount balanced on the new size, currency under the figure's end as today | `receipt_amounts_test` and `receipt_raster_test` green; a test that a six-figure total fits on 58 mm | revert |
| 5 | **Header and payment spacing**: header spaced from tokens, no gap without a logo; payment rows grouped by spacing, not rules | block tests; the raster measured with and without a logo | revert |
| 6 | **Previews, docs**: **after** PNGs of the nine cases; before/after notes; TEST_PLAN, TEST_REPORT, CHANGELOG; `/project-documentation update` | PNGs; real outputs | — |

Verify with `cd apps/xorder-pos && flutter analyze && flutter test test/features/receipt_*`, then the full suite and the baseline comparison.

## Impact and risks
- POS only; no migration, API, contract, permission or deploy-order change. Money, tax, discount and payment code is not touched; their tests must pass **unmodified** (AC-8).
- Tests that assert the old structure will change on purpose (rule count, footer lines); each is named in the report.
- The slip gets shorter (fewer rules and lines), which helps paper use.
- Preview-based validation is not printer validation: the 58 and 80 mm output on real hardware is for a person.
- The Arabic and mixed cases are checked on the shaped bitmap, not on paper.
- Domain lens: helps cafés (shorter slips, faster); food trucks and kitchens with paper cost; no model depends on tables or addresses.

## Approvals needed
- **Your go on this plan.** Nothing else (no migration, contract, payment or order change). No commit or push.
- Build sits on top of uncommitted receipt work; I will not revert or commit it.

## As built — differences from the plan
- Stage 5 (header and payment spacing) came out as the rule and gap changes of stage 2 plus the token scale; the header itself only changed size (title 38 → 34).
- Row labels and values also wrap fully (not only item names), and share a baseline, so a quieter label does not float; the plan said only "labels in the secondary size".
- `SlipOrnament`, its tokens, its drawing in both renderers and the heart glyph were removed rather than left unused.
- The logo's 120-dot maximum height (XORD-024 BR-2) was left as it is.
- The preview generator is `test/tool/receipt_previews_test.dart`; before images were made from the code before any edit.

# Receipt design system (presentation only) — receipt-design-system

Status: built, uncommitted · 2026-10-26 · Source: the owner's brief "XOrder — Receipt Design System & UI/UX Improvements" with a screenshot of the Arabic preview (kept in the conversation; 19 sections) · Verified against: xorder-pos `a6f5fe5` + a large uncommitted working tree, xorder-cloud `06bc8e3` (not touched)

## 1. Summary
Redesign how the receipt looks, on the paper and in the preview, without touching what it says: clearer hierarchy, a compact header, tidier metadata, a readable items table where no name is cut off, a calmer grand total, grouped payments, a shorter footer, fewer rules, one set of tokens. Money, tax, discounts, payments, the data model and tenant customisation stay as they are.

## 2. Why
The slip is correct but dense and uneven (the brief's list: the heavy total, repeated footer messages, too many separators, item names cut at two lines). It is the one page every customer reads.

## 3. Goal and success
A receipt that reads as a finished commercial product on 58 mm and 80 mm, in Arabic, English and mixed, with every figure and word the current one has.

## 4. Users, roles and permissions
No new permission. The printer settings stay behind `terminal.manage`; nothing changes who may print or reprint.

## 5. Today (verified in source, `apps/xorder-pos/lib/features/receipt/`)
| Fact | Where |
|---|---|
| One document model, two renderers: `ReceiptDocument.of` builds a list of `SlipBlock`s; the printer rasterises it (`receipt_raster.dart`, 984 lines) and the preview draws it as widgets (`receipt_paper.dart`, 598). Both read the same size table. | `receipt_document.dart:1-20`, `slip_style.dart:1-12` |
| Design tokens already exist: `SlipMetrics` (type sizes in dots at the 80 mm reference, margins, columns, rule thickness, logo max 120 dots). Not font families or colours. | `slip_style.dart:21-100` |
| Paper: 80 mm = 576 dots, 58 mm = 384 dots; content = width − 2×12 margin; a 58 mm slip is the 80 mm one scaled. | `printer_config.dart:21,25`, `SlipMetrics` |
| The brief's section names already exist as blocks: logo, name, phone/address, metadata rows, items header and rows, money rows, `SlipGrandTotal`, payment rows, footer, ornament. | `receipt_document.dart:200-520` |
| Item names are limited to **two lines with an ellipsis** on paper. | `receipt_raster.dart:562,571` (`maxLines: 2`) |
| An item row carries only name, quantity and **line total**. The receipt model has no unit price, modifiers, add-ons, variants, per-line discount or notes. | `ReceiptLine` `receipt_data.dart:39-59`; built at `:136` and `:216` |
| Currency code is printed beside every amount (owner decision D-1/BR-10 of 2026-10-26). | `docs/features/receipt-logo-and-layout/FEATURE.md` §7, §13 |
| Footer: the tenant's own `footerNote`, then "thank you", "look forward", a heart ornament, `xorder.io`, then the tax-from-device disclosure. | `receipt_document.dart` footer block |
| Rules: solid after the header, solid before the items, dashed before the money, heavy above the total, solid after the total, solid after the payments. | `receipt_document.dart` |
| Tests that read the blocks (not bitmaps): `receipt_document_test` (22), `receipt_amounts_test` (13), `receipt_raster_test` (9), `receipt_print_test` (20), `receipt_logo_raster_test`. **No golden-image tests exist.** | `test/features/` |
| Printing on real hardware: not testable here. | — |

## 6. Scope
**In:** the document builder's ordering and block choices, `SlipMetrics` tokens, both renderers, tests, before/after previews, docs.
**Out (the brief's own constraints §16):** calculations, tax, payment, order data, the receipt data model, printers and their drivers, tenant settings, cloud.

## 7. Behavior and business rules
- **BR-1** Every value on the slip today is still there, with the same figure. Only order, size, weight, spacing and rules may change.
- **BR-2** Preserve what the owner decided: currency beside every amount (BR-10 of `receipt-logo-and-layout`), decimal alignment (BR-8), logo first in the header (BR-1), XOrder only at the bottom (BR-7), the tenant's header and footer notes, REPRINT and REFUNDED stamps, PROVISIONAL, the ETA QR, the tax-from-device disclosure.
- **BR-3** An item name is never truncated: it wraps to as many lines as it needs and never overlaps the quantity or price column.
- **BR-4** One token table for type, weight, spacing, rules and logo size; no styling number outside it.
- **BR-5** The preview and the paper keep reading the same blocks and tokens.

## 8. Acceptance criteria
From the brief, restated for this code (each testable on the block list or on the raster):
- **AC-1** Sections are separable: branding, metadata, items, summary, grand total, payment, footer, in that order, with a stable rule/whitespace pattern.
- **AC-2** A long item name (Arabic, English, mixed) prints in full over several lines on 58 and 80 mm with the quantity and price columns untouched.
- **AC-3** Rules: no more than the agreed set (after branding, before the summary, around the total); all print on a one-bit head.
- **AC-4** Grand total: label and amount on one baseline pair, currency attached to the amount, smaller than today but still the largest thing on the slip, and a six-figure total fits on 58 mm.
- **AC-5** Footer: the default template says thanks once; a tenant `footerNote` is always printed; no blank footer block when empty; `xorder.io` stays last.
- **AC-6** Header: no gap when there is no logo; a long name or address wraps; the logo keeps its aspect ratio.
- **AC-7** Arabic RTL, English LTR and mixed: phone, amounts and currency codes keep their order.
- **AC-8** No calculation changes: the existing money, tax, discount and payment tests pass unmodified.
- **AC-9** Before/after previews of the nine cases in the brief §17 exist.
- **AC-10** Physical printing on 58 and 80 mm: **needs a person**; everything else is proven on the document and the bitmap.

## 9. Edge cases and failure modes
No logo, undecodable logo, many items, zero-value items, voided (struck) lines, repriced `*`, split payments, a negative discount row, `-0`, exponent-3 currencies, very long totals, 58 mm, a reprint, a refunded slip with its stamp. Printing must never fail because of the layout (the logo rule BR-4 of the earlier feature holds for every new block).

## 10. Impact
POS only. No cloud, API, schema or contract change; no deploy ordering. Touches `receipt_document.dart`, `slip_style.dart`, `receipt_raster.dart`, `receipt_paper.dart`, their tests. The queue re-renders old jobs from the document, so a queued slip prints in the new design after the update; that is intended.

## 11. Dependencies, known gaps, risks
- Without golden images, "visual regression" is an eyeball on generated previews plus structural tests (see §13).
- Real-printer validation is not possible in this environment.
- Modifiers, add-ons, variants, per-line discounts, notes and unit prices are **not in the receipt model** (§5); showing them is a model change the brief forbids unless necessary.
- The work is on top of other uncommitted receipt work (XORD-024/025/026 are unreleased).

## 12. How it will be tested
Existing block-level tests stay green unchanged for everything money-related; new block and bitmap tests for AC-1..7; generated PNG previews for AC-9; a person for AC-10.

## 13. Decisions and open questions
**Decided by the owner, 2026-10-26**
- **D-1 (was C-1)** Currency stays beside **every** amount (XORD-026 stands). The brief's "avoid repetition" is not applied.
- **D-2 (was C-2)** The default footer says thanks **once**: the "look forward" line and the heart ornament are dropped from the default. The tenant's own footer text and `xorder.io` stay.
- **D-3 (was C-5)** Visual regression = generated before/after PNG previews plus tests on the block list. **No golden-image tests.**

**Defaults taken, not asked (say if you disagree)**
- **C-3** Unit price, modifiers, add-ons, variants, per-line discounts and notes are **not** added: the receipt model has none and the brief forbids a model change unless necessary. If you want them, that is a separate approved change to `ReceiptLine` and its two builders.
- **C-4** Grand total amount 56 → 44 dots (still the largest text on the slip).
- **C-6** The currency under the grand total stays right-aligned under the figure (BR-9 of `receipt-logo-and-layout`, decided today), which is already "attached" to the amount; it is not moved onto the figure's line.

**Still open**
- Q-1 Exponent-3 currencies and the widest total that must fit on 58 mm (the earlier feature's Q-2 is still open).

## 14. As built (2026-10-26)
Built as planned in `TECHNICAL.md`; see `CHANGELOG.md`, `BEFORE_AFTER.md` and `TEST_REPORT.md`. C-3, C-4 and C-6 were taken at their defaults, not answered. AC-10 (real 58 and 80 mm printers) is not done.

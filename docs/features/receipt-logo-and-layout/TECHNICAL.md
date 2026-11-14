# Receipt: logo, aligned amounts, currency — technical plan

Slug `receipt-logo-and-layout` · Plan written 2026-10-26 · **Approved by the owner and built 2026-10-26** (see section 11 for what was built and where it differs from this plan).
Specification: [FEATURE.md](FEATURE.md) (BR-1…BR-11, AC-1…AC-14, findings XORD-024/025/026).
Repo touched: `apps/xorder-pos` only. Verified against xorder-pos `a6f5fe5`; the receipt files and `printer_*` files are clean in the working tree (the tree has about 80 other modified files, see "Mixed work" below).

## 1. What re-reading the code changed in the specification

| # | Finding | Effect on the plan |
|---|---|---|
| D-1 | Q-1 is answered: the Printer pane is behind `terminal.manage` (`management_printer_pane.dart:26`, `management_screen.dart:1045`). | The new switch uses it. No new permission. FEATURE §4 and Q-1 to be updated. |
| D-2 | `PrinterSettingsForm` rebuilds the config with `PrinterConfig(name:…, paperWidthDots:…)` in two places (`printer_settings_dialog.dart:197`, `:221`). A new field would be silently reset to its default on every printer or paper change. | Both become `copyWith`. A test pins it. |
| D-3 | The setup wizard builds its own `PrinterConfig` (`setup_controller.dart:975`). | Left alone: a fresh till defaults to logo on, as decided. |
| D-4 | The raster pins each money value at its **natural width** to the far edge (`receipt_raster.dart:408-450`), and the preview does the same (`receipt_paper.dart:237-262`). `textAlign` there has no effect, which is why Arabic figures share a left edge rather than a decimal point. The fix is a shared width for amount rows, not a changed `TextAlign`. | New `SlipRow.amount` flag; one shared width per slip. |
| D-5 | The preview cannot show the exact one-bit dither the printer produces, because the preview widget is synchronous and the dither is a pixel pass. | The preview shows the logo in greyscale at the same box. The real print is the reference. FEATURE BR-3 stays; AC-4 stays a person-check. |
| D-6 | A queued sale stores finished bytes (`pos_print_jobs.payload`); nothing re-renders it. | BR-6 is already true for retries; no code needed, one test to pin it. |
| D-7 | `ReceiptDocument.of` is called from five places and `ReceiptPaper` from four. | One provider supplies the logo; each call site passes `logo:`. |

Nothing else in FEATURE.md was contradicted.

## 2. Reuse (do not rebuild)
- The block list and the two renderers (`receipt_document.dart`, `receipt_raster.dart`, `receipt_paper.dart`); `SlipMetrics` for every size.
- `Money.format(withCurrency: true)` (`money.dart:120`). No new formatter.
- `businessLogoProvider` (`providers.dart:1327`): reads the till's own database, never throws, null when none. Used as is.
- `PrinterConfig` and `config.json` (tolerant reader); the Printer pane and its form. The `_Choice` look for the new toggle.
- The existing raster pass `ReceiptRaster.pack` stays as is for text and QR (50% luminance).
Not regressed: the ETA QR path, the REPRINT and REFUNDED stamps, split-payment rows, the refunded-stamp currency.

## 3. Impact
- **Files (all `apps/xorder-pos`):** `lib/features/receipt/{receipt_document,receipt_raster,receipt_paper,slip_style,receipt_dialog,reprint_dialog,receipt_preview_dialog}.dart`; new `lib/features/receipt/logo_bitmap.dart` (pure Dart, no Flutter); `lib/core/config/printer_config.dart`; `lib/features/settings/printer_settings_dialog.dart`; `lib/features/admin/presentation/management_receipt_pane.dart` (preview shows the logo); `lib/app/providers.dart` (`receiptLogoProvider`); `lib/core/l10n/app_strings.dart` (EN and AR).
- **API / contract / cloud:** none. **Schema / migrations:** none (the switch is a key in `config.json`). **Permissions:** none new, none narrowed. **Tenant isolation:** the logo read already selects by `restaurant_id` (`providers.dart:1337`).
- **Money and order state:** only the text of figures changes; no calculation, rounding or tax code is touched (BR-11).
- **Offline / outbox:** nothing leaves the till; queued jobs are byte snapshots.
- **Visible change to every receipt printed after this ships:** a wider price column, a currency code on each figure, a logo if one is set. Customers' and accountants' paper changes; that is the point, and it is why this plan asks for approval though none of the mandatory gates apply.
- **Deploy:** POS build only. Old tills keep printing the old slip; there is no contract between versions.

## 4. Domain lens (`FOOD_SERVICE_DOMAIN.md` §6)
- Café (counter, speed, paper cost): logo adds about 15 mm per slip, so the switch matters; no extra step at the till.
- Restaurant (reprints, split bills): every tender line and change line gets the code; a reprint carries the current logo (decided).
- Food truck (58 mm, offline, small menu): everything is scaled by 384/576; the logo is capped to 80 dots there; a logo problem can never stop a sale printing (BR-4); no network is used.
- Cloud kitchen: no counter slip; not affected. Delivery and aggregator slips are a known gap and out of scope.
- Mixed basket (Q4): every VAT line gets the code; totals are unchanged to the minor unit (AC-10).

## 5. Stages
Each stage ends with `flutter analyze` and its targeted tests; fix before continuing.

### Stage 1: currency on every amount and aligned amounts (XORD-025, XORD-026)
| Step | Change | Where |
|---|---|---|
| 1.1 | `SlipRow` gets `amount` (default false). Subtotal, discount, service, VAT lines, tender lines, paid and change set it. Their values and `SlipItem.price` use `format(withCurrency: true)`; discount stays `-` before the figure. The grand total keeps `amount` and `currency` separate. | `receipt_document.dart` |
| 1.2 | `priceColumn` 140 → 190 dots ("999,999.99 EGP" at the 22-dot mono face is about 185). Update the comment that says 140 holds a figure. | `slip_style.dart` |
| 1.3 | Raster: one `amountWidth` for the slip = the widest natural width among `amount` rows (capped at two thirds); amount rows pin that box to the outer edge and draw the text right-aligned, LTR. Items price and its heading are right-aligned in both languages. Total's currency paragraph is right-aligned to the figure. | `receipt_raster.dart` (`_row`, `_item`, `_itemsHeader`, `_grandTotal`) |
| 1.4 | Preview: the same rules. The amount width comes from a `TextPainter` over the same strings and the same `SlipMetrics` size; the total's column is `CrossAxisAlignment.end`. | `receipt_paper.dart` |
Tests (written with the stage):
- `receipt_document_test`: every `amount` row and item price ends with ` EGP`; non-amount rows (date, time, order number, cashier, terminal, order type, payment method) do not; discount reads `-30.00 EGP`; the document's figures equal the engine's to the minor unit (AC-10); no block above the footer mentions "xorder" and the last block is `xorder.io` (AC-12, BR-7).
- `receipt_raster_test`: a document of three amount rows (`1,050.00 EGP`, `450.00 EGP`, `63.00 EGP`) in Arabic and in English; the right edge of each inked line is equal within one dot (fails before the change in Arabic); the currency line under a grand total ends where the figure ends within two dots (AC-8, AC-9); a long Arabic item name with a seven-digit total clips nothing at 576 and 384 dots (AC-11).
- `ReceiptPaper` widget test (new, in `receipt_document_test` or a sibling): right edges of the amount paragraphs measured through `RenderParagraph` are equal in Arabic and English; the preview and document list the same blocks in the same order (AC-14).
- Existing assertions of bare figures in `receipt_document_test`, `receipt_print_test`, `reprint_test`, `receipt_raster_test` change deliberately; each is updated and named in the report. **UNVERIFIED which ones**: found by running the suite after step 1.1.
Rollback: revert the stage; no data or config is involved.

### Stage 2: the logo (XORD-024)
| Step | Change | Where |
|---|---|---|
| 2.1 | `PrinterConfig.printLogo` (default true): constructor, `copyWith`, `toJson` key `print_logo`, tolerant `fromJson` (absent or not a bool reads true). Both rebuilds in the form become `copyWith`. | `printer_config.dart`, `printer_settings_dialog.dart` |
| 2.2 | A "Print logo on receipts" toggle with a one-line hint in the Printer form, saved with the existing Save. EN and AR strings. | `printer_settings_dialog.dart`, `app_strings.dart` |
| 2.3 | `LogoBitmap.oneBit(rgba, width, height)` in pure Dart: alpha composited onto white, then Floyd-Steinberg error diffusion to black or white. | new `logo_bitmap.dart` |
| 2.4 | `SlipLogo(bytes)` block; `ReceiptDocument.of(…, logo:)` adds it first after the REPRINT/REFUNDED stamps, only when `logo` is non-empty. | `receipt_document.dart` |
| 2.5 | Raster: for a `SlipLogo`, decode, size to fit `min(content width, 120 dots x scale)` without enlarging, re-decode at that size, dither, draw at whole-dot coordinates with no antialiasing, centred, with the usual gap. Any exception (undecodable, zero size) skips the block, so the slip prints as it does today (BR-4). Images are disposed. | `receipt_raster.dart` |
| 2.6 | Preview: `Image.memory` in a box with the same width and height caps, greyscale filter, `errorBuilder` empty. Documented as an approximation of the dither. | `receipt_paper.dart` |
| 2.7 | `receiptLogoProvider`: logo bytes when `printerConfig.printLogo` and a logo exists, else null; never throws. The print paths `await` it inside a try, falling back to null; the previews `watch` it. Passed at `receipt_dialog` (preview and print), `reprint_dialog` (preview and print), `receipt_preview_dialog`, and `management_receipt_pane` (preview). | `providers.dart` + call sites |
| 2.8 | Remove the stale "No logo…" comment. | `receipt_document.dart` |
Tests:
- `logo_bitmap_test` (pure): fully transparent becomes all white; black stays black; mid-grey is about half ink; light yellow still has ink (the case a plain threshold loses); output size equals input.
- `receipt_document_test`: logo present puts `SlipLogo` first after stamps and before the name; absent, empty, or switch off gives today's blocks exactly (AC-1, AC-3).
- `receipt_raster_test` with logos made in-test through `dart:ui`: a PNG gives more ink in the header band than no logo, and the logo is no wider than the content and no taller than 120 dots at 576 and 80 at 384; name, registration number, QR and thank-you are still present; corrupt bytes give a bitmap identical to no logo (AC-2, AC-3, AC-13). A transparent PNG and a light-coloured PNG each leave ink (the machine part of AC-4).
- `receipt_print_test`: `buildJob` with a logo is longer than without and still ends with feed and cut; a queued job's stored bytes are unchanged after the logo changes (AC-6); `reprint_test`: the rebuilt slip carries the current logo.
- `printer_config` / `printer_settings_test`: JSON round trip; an old file without the key reads true; a non-bool reads true; saving after changing the paper width keeps the switch (D-2); the toggle saves (AC-7).
- Provider test: switch off gives null; no logo gives null; both modes read the same row (AC-5, offline and cloud differ only in how the row got there, covered by XORD-021's tests).
Rollback: revert the stage; `config.json` files with `print_logo` are read by older builds, which ignore unknown keys (the reader is tolerant).

### Stage 3: close-out
`/project-documentation update receipt-logo-and-layout` (FEATURE status, TECHNICAL as built, API and DATABASE "none", TEST_PLAN matrix, TEST_REPORT with real output, CHANGELOG); update `pos-receipts-printing` in the inventory; tracker rows XORD-024 to 026 and section 8 (ticks only for criteria a test that ran proves, named beside the tick); `bash scripts/harness/verify.sh`.

## 6. Verification commands
```
cd apps/xorder-pos
flutter analyze
flutter test test/features/receipt_document_test.dart test/features/receipt_raster_test.dart test/features/receipt_print_test.dart test/features/reprint_test.dart test/features/printer_settings_test.dart test/features/printer_pane_test.dart test/features/receipt_profile_ui_test.dart
flutter test            # full suite; baseline 2026-10-26: +3178 ~79, all passed
```
PostgreSQL-tagged suites self-skip without `POS_PG_HOST` and will be reported as not run; nothing in this change needs them.

## 7. What no test here can prove (listed for a person)
- A logo's look on a real 80 mm and 58 mm thermal printer, in Arabic and English (AC-4). A test can only show that ink is present and sized.
- The slip as the preview draws it versus the paper: the preview's greyscale logo is an approximation.
- That the wider price column is comfortable on a 58 mm roll (the slip scales by 384/576).
- Acceptance of the new look by the owner.

## 8. Mixed work
`apps/xorder-pos` has about 80 modified or staged files from other work (including XORD-021, XORD-022 and XORD-005 edits and `management_receipt_pane.dart`). This change touches `management_receipt_pane.dart` and `receipt_profile_ui_test.dart`, which already carry the 2026-10-26 logo-card move. Nothing will be committed here; when you commit, split these by finding.

## 9. Approvals needed
None of the mandatory gates apply (no migration, no contract, no order or payment logic, no permission narrowed, nothing near cloud `main`). Your go is needed because every receipt a till prints will look different.

## 10. Open questions
- Q-2 (carried over): which currencies must fit the price column. Plan assumes `EGP`-length codes and 2 decimals; a three-decimal currency such as KWD would need about 205 dots. I propose 190 now and a measured width later if the product adds such a currency.
- Q-4: the toggle's wording. Proposed English "Print logo on receipts"; Arabic "طباعة الشعار على الإيصالات". The Arabic is my proposal and needs your read.

## 11. As built (2026-10-26)
Stages 1 and 2 are built as planned; every file in section 3 changed, plus the ones below. Tests and their real results: TEST_PLAN.md and TEST_REPORT.md.

**Differences from the plan**
- **Preview measured with the wrong style.** The plan said the preview would measure amounts with a `TextPainter` over the same strings and sizes. That was not enough: a `Text` also inherits the theme's default style, so the text was wider than its box and the code wrapped under the figure (found by the new preview test). `_Slip` now takes the default text style and text scale from its context and merges them into the measurement (`receipt_paper.dart`).
- **The total's figure is right-aligned in its own box** in the preview, so the code under it ends at the figure, not at a box a little wider than the glyphs.
- **The switch hint is its own line** under the checkbox, not the checkbox's right-hand detail text (too narrow). The checkbox reuses the Printer form's `_Choice` with a `checkbox` mode.
- **Dither done before drawing, in pure Dart** (`logo_bitmap.dart`, Floyd-Steinberg, alpha over white), as planned; the logo is decoded at its final size and drawn 1:1 at whole-dot coordinates with no antialiasing, so the packer's 50% threshold leaves it alone.
- **Print paths await the logo first** (`receipt_dialog.dart`, `reprint_dialog.dart`), then build the slip. A test that prints with a logo has to wait for the job, not for a fixed time.
- **Not built:** a test that a queued job's stored bytes are unchanged after the logo changes (nothing re-renders a stored job; see TEST_PLAN AC-6b); a named assertion on the change line (AC-10b).

**Files touched** (all `apps/xorder-pos`): `lib/features/receipt/{receipt_document,receipt_raster,receipt_paper,slip_style,receipt_dialog,reprint_dialog,receipt_preview_dialog}.dart`, new `lib/features/receipt/logo_bitmap.dart`; `lib/core/config/printer_config.dart`; `lib/features/settings/printer_settings_dialog.dart`; `lib/features/admin/presentation/management_receipt_pane.dart` (preview shows the logo); `lib/app/providers.dart` (`receiptLogoProvider`); `lib/core/l10n/app_strings.dart`. Tests: new `receipt_amounts_test`, `logo_bitmap_test`, `receipt_logo_raster_test`, `receipt_logo_provider_test`; extended `receipt_document_test`, `receipt_print_test`, `printer_settings_test`; updated `reprint_test`.

**Formatting noise.** Running `dart format` over `lib/features/receipt` also reformatted three files the change did not otherwise need to touch: `receipt_printing.dart` (5 lines), and wrapping changes in `reprint_dialog.dart` and `receipt_dialog.dart` beyond the logo edits. They are format-only. Reverting them with `git checkout` was declined by the sandbox and was not worked around; split them out when committing, or revert them by hand.

**Risks left.** The 190-dot price column and the logo on a real printer are unverified (section 7). Long Arabic dish names wrap more than before at the same width; the test font cannot show how much.

## 12. Review (2026-10-26, a separate read-only reviewer given only the specification and the files)
Findings, and what was done:
| # | Finding | Result |
|---|---|---|
| 1 | Medium: an item price wider than the fixed 190-dot column (e.g. `1,000,000.00 EGP`) printed cut to an ellipsis; the "nothing is cut off" test only checked margins | **Fixed.** The price column now grows to the widest price on the slip, up to 45% of the paper, in both the raster and the preview. New tests for both fail on the old fixed column. |
| 2 | Medium: a reprint was recorded in the audit ledger, then the logo was awaited, then `if (!mounted) return`, so a dialog dismissed in that gap left a recorded reprint that never printed | **Fixed.** The logo is read before the reprint is recorded. (The sale dialog was safe: `barrierDismissible: false`.) No test of the dismissal itself. |
| 3 | Low: the preview logo ignored the paper scale (a 64 px logo previewed about twice as large as it prints) and decoded a 4096 px upload in full | **Fixed.** `scale: 1 / scale`, `cacheWidth` and a width cap. A test with a real PNG measures it. |
| 4 | Low: weak tests (an undecodable "logo" proved nothing about position; a test named "only black and white" asserted ink only; the QR test compared heights only) | **Fixed.** Real PNGs in the preview tests; the coloured-logo test now bounds the ink between a blank and a solid block; the QR test now compares every dot under the logo with the slip without one. AC-4 "photographic" still has no fixture. |
| 5 | Low: the setup wizard builds a fresh `PrinterConfig`, so running setup again turns the logo back on | **Accepted, not changed.** Setup writes the whole file; defaulting to on is the decision (D-2). |
| 6 | Low: the logo was decoded twice, and a placed image could leak if a later block threw | **Fixed.** Size read from the file header (`ImageDescriptor`); images disposed in an outer `finally`. |
Areas the reviewer reported clean: money (no calculation changed), the dither bounds, 58 mm sizing, drawer and queue ordering, `PrinterConfig` copy/parse, RTL alignment, XOrder-in-footer.

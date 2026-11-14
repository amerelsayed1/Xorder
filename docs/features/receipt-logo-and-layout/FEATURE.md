# Receipt: logo, aligned amounts, currency on every amount — receipt-logo-and-layout

Status: **implemented, awaiting a real print and the owner's look** · 2026-10-26 · Source: the owner's request, 2026-10-26 (quoted below) · Verified against: xorder-cloud `06bc8e3` (not touched), xorder-pos `a6f5fe5` plus an uncommitted working tree (receipt files themselves are clean; `management_receipt_pane.dart` is dirty from the XORD-021 move, see section 6)

Findings opened for this: **XORD-024** (logo on the receipt), **XORD-025** (amounts and currency label misaligned), **XORD-026** (currency missing on most amounts). They are separate symptoms and keep separate numbers; they ship together because they change the same slip.

> The owner, with a screenshot of the Arabic preview: "it should appear in the invoice [the logo]… Also there alignement issue here needed to be fix. Also miss to show currency in some fields. If we need to show xorder it will be in bottom footer."

## 1. Summary
Print the restaurant's own logo at the top of the receipt, line the amounts up so decimals sit under each other in Arabic as they do in English, and show the currency code beside every amount rather than once under the total. XOrder's own mark stays out of the header: it appears only in the footer line that is already there.

## 2. Why
- A restaurant that chose a logo (XORD-021) sees it on the start screen but not on the paper the customer takes home. The receipt requirement (`POS-R100`, `docs/pos/02-pos-requirements.md:180`) already lists the logo in the header.
- On the Arabic slip the amounts are pushed to the left edge and start at the same x, so `450.00` over `63.00` do not line up on the decimal point; a column of different-sized figures reads as ragged and is harder to check by eye. The `EGP` label under the big total floats in the middle of the figure.
- A customer, an accountant or an inspector reading one line cannot tell the currency. The screen shows it everywhere (commit `a6f5fe5`), the paper does not.
- Venue models: all four print slips. Cafés print most (speed, paper cost); food trucks often use 58 mm rolls and run offline; restaurants reprint and split bills (several tender lines); a cloud kitchen has no counter slip, so this mostly does not apply to it.

## 3. Goal and success
- A receipt printed or previewed for a restaurant that has a logo shows that logo above the name, legible in black and white, without pushing the ETA QR, registration number or thank-you off the paper.
- Every stack of amounts has its decimal points in one vertical line, in Arabic and in English.
- Every amount on the slip carries its currency code.
- No XOrder branding above the footer.
- Proof: document, raster and preview tests (section 12), plus one person looking at a real slip from a real printer (cannot be automated).

## 4. Users, roles and permissions
| Who | What | Permission today |
|---|---|---|
| Owner / holder of `business.branding.manage` | Chooses or removes the logo (already built, XORD-021) | `business.branding.manage` (`permissions.dart`) |
| Whoever edits the till's printer settings | Turns "print logo on receipts" on or off | `terminal.manage` (the Printer pane's own gate, `management_printer_pane.dart:26`); no new permission |
| Cashier | Prints and reprints; cannot change any of this | unchanged |

## 5. Today (verified in source)
**Logo.**
- `receipt_document.dart:211` says "No logo… neither the receipt profile nor the tenant carries an image". Stale: since XORD-021 the till stores one on `pos_restaurants` (`logo_bytes`, `logo_mime`, `logo_source`), read for both offline and cloud tills by `businessLogoProvider` (`providers.dart:1327`); validated PNG or JPEG, 2 MB, 64–4096 px per side (`business_logo.dart`).
- The slip is a list of blocks (`SlipBlock`, `receipt_document.dart:48`) walked by two renderers: the preview widget `ReceiptPaper` and the printer bitmap `ReceiptRaster`. There is no image block.
- Printing: the whole slip is drawn to a bitmap and thresholded at 50 % luma to one bit (`receipt_raster.dart:71`); dithering was rejected for text, comment at `:67`. 80 mm is 576 dots, 58 mm is 384; the slip is laid out at the 80 mm reference and scaled (`slip_style.dart`).
- A queued job (printer unreachable) stores the **finished ESC/POS bytes** (`pos_print_jobs.payload`, `migrations.dart:3163`, "sent verbatim on retry"), so a retry reprints exactly what the sale printed; only an explicit **reprint** rebuilds the slip (`reprint_dialog.dart:220`).
- Callers that build a slip: `receipt_dialog.dart:256`, `reprint_dialog.dart:220`, `receipt_paper.dart:71`, plus previews in `receipt_preview_dialog.dart` and `management_receipt_pane.dart:368`.
- `PrinterConfig` (`printer_config.dart`) is per terminal, saved in `config.json`, tolerant of unknown or missing keys; it holds `name` and `paper_width_dots`.

**Alignment** (checked in the screenshot and the code).
- In an Arabic slip the amount side of every row is `_outer` = left (`receipt_paper.dart:126`). For the money rows the value is shrink-wrapped at the row's end (`receipt_paper.dart:237-262`), so figures of different length share a **left** edge instead of a decimal point: in the screenshot `450.00` ends further right than `63.00`. The items column (`:308-330`) is left-aligned the same way, so `1,050.00` over `150.00` would not line up. In English the same code right-aligns, which is correct.
- The currency under the total is centred under the figure in both renderers (`receipt_paper.dart:358-364`, `receipt_raster.dart:582-590`): in the screenshot `EGP` sits mid-figure.
- Checked, no defect found: quantity column (centred under its heading), label/value rows, the stamp, the dashed and heavy rules.
- Observation, not part of this change: the "الجهاز" (device) row shows the word "الكاشير". It prints `session.terminalCode` (`receipt_dialog.dart:263`), so it is probably that till's own code or name. **UNVERIFIED**.

**Currency.**
- Only the grand total prints a code (`SlipGrandTotal.currency`, `receipt_document.dart:343`). Line prices, subtotal, discount, service, each VAT line, tender lines, paid and change are bare (`:288-377`), and the refunded stamp already includes it (`:208`).
- This was deliberate: commit `a6f5fe5` ("Show the currency beside every on-screen money amount") left "the printed slip" bare because "the slip already prints the currency once under TOTAL". This request reverses that for the slip.
- `Money.format(withCurrency: true)` already produces `450.00 EGP` (`money.dart:120`). No money rule or rounding changes.
- The price column is 140 dots at the 80 mm reference and "holds `999,999.99` in the body mono" (`slip_style.dart:53-57`); adding ` EGP` needs about 190.

**XOrder branding.** `xorder.io` is the small line under the ornament (`receipt_document.dart:413`); nothing in the header. Already as requested; no test pins it.

## 6. Scope
In: logo block on the slip (preview and print); the "print logo" switch; end-aligned amounts in the items column and the money rows; total currency alignment; currency on every amount; tests; feature docs.
Out: cloud code, API, database or contract changes; the receipt profile and its form; the ETA QR and tax content; money arithmetic, rounding and tax rules; a per-order logo snapshot; delivery and kitchen slips; XORD-021's choose/remove UI.
Working-tree note: `apps/xorder-pos` has about 80 modified files from other work, and `management_receipt_pane.dart` plus `receipt_profile_ui_test.dart` carry the 2026-10-26 XORD-021 change. Do not mix them into the same commit.

## 7. Behavior and business rules
- **BR-1 Logo placement.** The logo is the first block of the header, centred, above the restaurant name and below any REPRINT or REFUNDED stamp. Print and preview show the same.
- **BR-2 Logo size.** Width at most the content width, height at most 120 dots at the 80 mm reference (about 15 mm of paper), aspect ratio kept, never enlarged past its own pixels. The 58 mm slip scales like everything else.
- **BR-3 Black and white.** The logo is converted for a one-bit head so it stays recognisable: transparent areas become white, light colours do not vanish into white, and a photographic logo is not a black blob. The method (threshold or dither of the logo region only) is the plan's choice; the text and QR keep their current 50 % threshold.
- **BR-4 Cannot fail the slip.** No logo, an undecodable logo or any error reading it prints the slip as today, with nothing in its place and no XOrder mark. A logo can never stop a receipt printing, queue it wrongly or hold up the cash drawer.
- **BR-5 Switch.** "Print logo on receipts", per till, **on by default**, so a till that already has a logo prints it after the update. Off prints and previews exactly as today. It lives in the printer settings (`PrinterConfig`, `config.json`), not the database; a config without the key reads as on.
- **BR-6 Reprints** use the logo the till holds now. A queued sale keeps the bytes it was first built with (existing behavior, unchanged).
- **BR-7 XOrder.** The XOrder name or mark never appears above the footer. `xorder.io` stays as the last footer line.
- **BR-8 Amount alignment.** Within one block of amounts (items column, money rows, tender lines) the figures are right-aligned as left-to-right text, so decimal points share one vertical line, on an Arabic slip as well as an English one. The column keeps its side (the left on an Arabic slip, the right on an English one). The column heading ("السعر" / "Price") sits over the end of the figures.
- **BR-9 Total currency.** The code under the big total is aligned to the figure's end (its right edge), not centred.
- **BR-10 Currency.** Every amount on the slip is followed by the currency code in the same string as the figure (`150.00 EGP`): line prices, subtotal, discount (`-30.00 EGP`), service, each VAT line, each tender line, paid, change. The refunded stamp is unchanged. The grand total keeps its code under the figure. The price column is widened so the longest expected figure and code fit on one line; item names may wrap to their existing two-line limit.
- **BR-11 Money untouched.** Only formatting changes: `data.*.format()` becomes `format(withCurrency: true)`; no calculation, rounding or tax rule moves.

## 8. Acceptance criteria
- **AC-1** Given a restaurant with a logo and "print logo" on, when a receipt is built, then its first non-stamp block is a logo block carrying that logo's bytes, above the name. *(document test)*
- **AC-2** Given the same, when the slip is rasterised at 576 and 384 dots, then the bitmap has ink in the logo area, the logo is no wider than the content and no taller than 120 dots (scaled), and the name, QR, registration number and thank-you are still on the paper. *(raster test)*
- **AC-3** Given no logo, a logo that will not decode, or the switch off, then the slip is identical to today's, and printing still succeeds. *(document and raster tests, including corrupt bytes)*
- **AC-4** Given a logo that is a transparent PNG, a light-coloured logo and a photographic logo, then each is still visible after conversion. *(raster tests on fixtures; **a person must look at the printed result**)*
- **AC-5** Given a cloud till and an offline till, then the logo printed is the one the till holds (cloud: the platform's, synced). *(provider-level test with both modes)*
- **AC-6** Given a queued receipt, when the printer comes back, then the stored bytes print unchanged. Given a reprint, then it carries the current logo. *(print and reprint tests)*
- **AC-7** Given the printer settings, then the switch shows, defaults on, saves, and an old `config.json` without the key still reads as on. *(widget test; config round-trip test)*
- **AC-8** Given amounts of different lengths (`1,050.00`, `450.00`, `63.00`), when the slip is drawn in Arabic and in English, then their decimal points have the same x. *(raster test measuring the placed text; widget test on the preview)*
- **AC-9** Given the total, then its currency code is right-aligned to the figure in both renderers. *(raster and widget tests)*
- **AC-10** Given a sale with a discount, service charge, two VAT rates, a split payment and change, then every amount line ends with the currency code, and the document totals are unchanged to the minor unit. *(document test; a money regression test)*
- **AC-11** Given a long Arabic item name and a seven-digit total, then nothing is clipped or overlaps, at 80 mm and 58 mm. *(raster and widget tests)*
- **AC-12** Given any slip, then no block above the footer contains "xorder" and the last footer line is `xorder.io`. *(document test)*
- **AC-13** Given the ETA QR is present, then it still prints in full below the money. *(existing QR tests stay green; one new case with a logo)*
- **AC-14** Preview and print agree: the same blocks in the same order for the same input. *(existing document-parity tests extended)*

## 9. Edge cases and failure modes
- Offline and retry: the logo is read from the till's own database, no network; queued jobs are byte snapshots, so the logo cannot arrive late.
- Decoding is asynchronous; the slip must still build when the logo read is slow or throws (BR-4).
- Large logo: 2 MB is the stored limit, 4096 px; downscale before drawing so printing stays fast (the queued payload is a one-bit bitmap, so size on the wire is bounded by the width).
- Arabic and digits: amounts stay Latin digits, left to right, inside an Arabic slip (house rule); the code is Latin letters.
- Other currencies and exponents: three-decimal currencies (`1,000.000 KWD`) are longer than `EGP`; the column must fit them (**UNVERIFIED**: which currencies the product supports).
- Negative figures (discount, refunds) keep the minus on the left of the figure.
- Multi-tenant: the logo is the till's own restaurant row, selected by `restaurant_id`; no cross-tenant read exists in the new path.
- Plan and licence: none involved.
- Paper: 120 dots is about 15 mm per receipt, so the switch exists for owners who print many slips.

## 10. Impact
- **Apps:** POS only (`apps/xorder-pos`). Files expected: `lib/features/receipt/{receipt_document,receipt_paper,receipt_raster,slip_style,receipt_dialog,reprint_dialog,receipt_preview_dialog}.dart`, `lib/core/config/printer_config.dart`, `management_printer_pane.dart`, `management_receipt_pane.dart` (preview), `app_strings.dart` (EN/AR for the switch), tests under `test/features/`.
- **API / contract:** none. Cloud untouched; no `POS-BE-xxx` item.
- **Data / migrations:** none (the switch is in `config.json`; the logo column already exists).
- **Permissions:** none new.
- **Localization:** one switch label and hint, English and Arabic.
- **Documentation:** this folder; `docs/qa/XORDER_QA_FINDINGS.md` (XORD-024 to 026); `/project-documentation update` for `pos-receipts-printing` (no verified entry exists yet, inventory row is `pending` and `UNVERIFIED`).
- **Deploy order:** POS build only; nothing waits on cloud.

## 11. Dependencies, known gaps, risks
- Depends on XORD-021 (logo storage, sync). It is implemented but not yet seen running, so the first real logo on a slip is also the first real use of that data.
- Risk: thresholding a logo on a thermal head can look bad; hence a person must check a real print, and BR-3 leaves the method open.
- Risk: the wider price column narrows item names, more two-line wraps on long Arabic dish names, and every golden or figure-asserting receipt test changes at once.
- Risk: the 58 mm roll scales the slip by 384/576; a 190-dot price column is small there. Check on a 58 mm printer.
- Reverses the decision recorded in commit `a6f5fe5`; this document is the record of the reversal.
- Known gaps from the domain doc: none relied on. Delivery or aggregator slips are a known gap and out of scope.

## 12. How it will be tested
| Check | Where | Notes |
|---|---|---|
| Logo block, order, absence, switch, corrupt bytes | `test/features/receipt_document_test.dart` | pure, no widget tree |
| Bitmap contains the logo, sizes at 576 and 384, name and QR still present | `test/features/receipt_raster_test.dart` | headless |
| Decimal alignment, total currency, Arabic and English | raster measurement plus widget test of `ReceiptPaper` | |
| Currency on every amount, totals unchanged | `receipt_document_test.dart` | money regression included |
| Config switch round trip, old file | `printer_config` tests, `printer_settings_test.dart` | |
| Queue keeps bytes; reprint uses current logo | `receipt_print_test.dart`, `reprint_test.dart` | |
| Real printer: logo legibility, 80 mm and 58 mm, Arabic | **a person** | hardware; cannot be proven by a test |
Commands at plan time: `flutter analyze`, `flutter test test/features/receipt*`, then the full `flutter test`.

## 13. Decisions and open questions
**Decided by the owner, 2026-10-26**
- D-1 Currency is shown beside **every** amount.
- D-2 Logo prints **automatically when a logo is set**, with a switch to turn it off.
- D-3 A reprint uses **the current logo**.
- D-4 XOrder, if shown, is **only in the bottom footer**.

**Assumed, to confirm in the plan** (not asked; written down)
- A-1 The switch is per till (config file), not per branch or restaurant.
- A-2 "Alignment issue" means the decimal alignment and the total's currency label described in section 5; the owner did not say more. If something else looks wrong on the real slip, a new XORD number is opened.
- A-3 The logo is centred, above the name, at most 120 dots tall.

**Still open**
- Q-1 (answered 2026-10-26 by the plan): the Printer pane is gated by `terminal.manage`; the switch uses it.
- Q-2 Which currencies must fit the column (exponent 3?).
- Q-3 Suggestion, not asked: should the header's `ADMIN` cashier name and the terminal code be shown differently on an Arabic slip? Left alone.

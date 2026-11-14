# Test plan — receipt-logo-and-layout

Criterion → test. Written 2026-10-26 from FEATURE.md; results are in TEST_REPORT.md. Everything is in `apps/xorder-pos`.

| AC | What is proved | Test (file: name) | Kind |
|---|---|---|---|
| AC-1 | Logo is the first block after any stamp, above the name | `receipt_document_test`: "the logo (XORD-024) is the first block…", "comes after the REPRINT stamp…" | unit |
| AC-2 | Printed logo is no wider than the content, no taller than 120 dots (80 at 58 mm); the rest of the slip and the QR stay | `receipt_logo_raster_test`: "the logo alone …" (80 mm, 58 mm), "the slip with a logo … QR still prints" | unit (bitmap) |
| AC-3 | No logo, empty, undecodable, or switched off: the slip and the print job are exactly as before | `receipt_document_test`: "no logo, or an empty one…"; `receipt_logo_raster_test`: "a logo that will not decode prints the slip exactly as without one"; `receipt_print_test`: "and not when this till is set to leave it off", "a logo nobody can decode costs the sale nothing" | unit, widget |
| AC-4 | A light or transparent logo is not lost; a transparent border is not printed (machine part only) | `logo_bitmap_test`; `receipt_logo_raster_test`: "what a bad or pale logo does" | unit. **A person must look at a real print.** |
| AC-5 | Cloud-sourced and locally authored logos read the same | `receipt_logo_provider_test`: "is the same for a logo the platform sent…" | unit |
| AC-6 | A reprint prints the logo the till holds now | `receipt_print_test`: "a reprint prints the logo the till holds now" | widget |
| AC-6b | A queued job's bytes are unchanged after the logo changes | **no new test**: nothing re-renders a stored job (`pos_print_jobs.payload`, sent verbatim); the existing queue tests cover the storage | gap, stated |
| AC-7 | Switch shows, defaults on, saves, survives other printer edits; an old file reads as on | `printer_settings_test`: "print logo on receipts (XORD-024)" (5) | widget + unit |
| AC-8 | Decimal points line up in Arabic and English, at 80 and 58 mm, in amount rows, items column and the preview | `receipt_amounts_test`: "amount rows on the printed slip", "the items column", "the preview amounts end together" | unit (bitmap) + widget |
| AC-9 | Code under the total ends where the figure ends | `receipt_amounts_test`: "the currency under the total", "the preview … code ends under the figure" | unit + widget |
| AC-10 | Every amount ends with the currency code; figures equal the engine's to the cent | `receipt_document_test`: "the currency is printed beside every amount (XORD-026)" (4) | unit |
| AC-10b | A change line carries the code | **not asserted by name**: set by the same code path as "Amount Paid"; no sale in the suite gives change | gap, stated |
| AC-11 | Nothing clipped with a long Arabic name and a seven-digit total | `receipt_amounts_test`: "nothing is cut off" (80 and 58 mm) | unit (bitmap) |
| AC-12 | No "xorder" above the footer; `xorder.io` is in the footer | `receipt_document_test`: "XOrder is only in the footer" | unit |
| AC-13 | The QR is intact under a logo | `receipt_logo_raster_test`: "the QR still prints in full under a logo" | unit |
| AC-14 | Preview and print list the same blocks | existing parity test in `receipt_document_test` (now also covers `SlipLogo`) | widget |

Mutation checks run (the change was put back temporarily and the named tests had to fail): old amount pinning, centred code under the total, un-boxed preview amounts, left-aligned item prices, plain threshold instead of dither, the form rebuilding the config, the switch ignored. Results in TEST_REPORT.md.

Needs a person (cannot be a test here): the logo on a real 80 mm and 58 mm thermal printer in Arabic and English; the 58 mm column width; the owner's acceptance of the new look; the preview's greyscale logo as an approximation of the dither.

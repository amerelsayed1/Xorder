# Before and after — receipt-design-system
2026-10-26. Pictures are the **one-bit bitmap the printer would be sent**, drawn with the bundled fonts by `apps/xorder-pos/test/tool/receipt_previews_test.dart` (run with `RECEIPT_PREVIEW_DIR=<folder> flutter test test/tool/receipt_previews_test.dart`). They are not photographs of paper: margins, thermal contrast and head wear on a real roll still need a person.

The amounts are **sample data, not a real sale**. In case 8 the generator counts the voided line in the subtotal and pays more than the total, so its figures do not add up; the layout comparison is unaffected because before and after use the same data.

| Case | Before | After |
|---|---|---|
| 1 Arabic, 80 mm | `previews/before/1-ar-80.png` | `previews/after/1-ar-80.png` |
| 2 Arabic, 58 mm | `previews/before/2-ar-58.png` | `previews/after/2-ar-58.png` |
| 3 English, 80 mm | `previews/before/3-en-80.png` | `previews/after/3-en-80.png` |
| 4 English, 58 mm | `previews/before/4-en-58.png` | `previews/after/4-en-58.png` |
| 5 Mixed Arabic and Latin, 80 mm | `previews/before/5-mixed-80.png` | `previews/after/5-mixed-80.png` |
| 6 Thirty items, Arabic, 80 mm | `previews/before/6-many-items-ar-80.png` | `previews/after/6-many-items-ar-80.png` |
| 7 Long names, Arabic 58 mm and English 80 mm | `previews/before/7-long-names-*.png` | `previews/after/7-long-names-*.png` |
| 8 Discount, service, two tax rates, split bill, 80 mm | `previews/before/8-discount-tax-split-en-80.png` | `previews/after/8-discount-tax-split-en-80.png` |
| 9 No logo, no address, English 80 mm | `previews/before/9-no-logo-en-80.png` | `previews/after/9-no-logo-en-80.png` |

## What changed on the slip
| Area | Before | After |
|---|---|---|
| Separators | six rules | three: after the branding, dashed before the money, heavy above the total; space elsewhere |
| Facts (date, time, order number, cashier, till, order type) | label and value the same size | label in the smaller secondary size, value in body, on one baseline |
| Item names | stopped at two lines with `…` | the whole name, any number of lines, never into the quantity or price columns |
| Item spacing | 4 dots between items | 8 dots |
| Row labels and values (cashier, tender, tax…) | stopped at two lines with `…` | wrap fully |
| Business name | 38 dots | 34 dots |
| Grand total | 56 dots | 44 dots; label 34 → 30; currency still under the figure's end |
| Payment | under a rule | grouped by space under the total |
| Footer | the restaurant's text, thanks, "we look forward", a heart, `xorder.io` | the restaurant's text, thanks, `xorder.io` |
| Spacing and type | a number per block | a named scale (`spaceXs`…`spaceSection`) and named roles in `SlipMetrics` |

## What did not change
Every figure, label and total; the currency code beside every amount (XORD-026); decimal alignment (XORD-025); the logo's size and placement (XORD-024); the tenant's header and footer text; REPRINT and REFUNDED stamps; PROVISIONAL; the ETA QR; the tax-from-device disclosure; the receipt data model; the printer drivers.

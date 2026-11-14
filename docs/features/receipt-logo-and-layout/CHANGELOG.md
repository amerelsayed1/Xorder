# Changelog — receipt-logo-and-layout

## 2026-10-26
- **Added** the restaurant's logo at the top of the printed and previewed receipt (XORD-024). Converted to black and white by error diffusion, at most 120 dots tall, never enlarged, centred; a logo that cannot be read is skipped and the receipt prints as before. New setting **Print logo on receipts** (Settings › Printer & cash drawer), on by default, per till, stored in `config.json` (`print_logo`). Reprints use the current logo.
- **Changed** every amount on the receipt now ends with the currency code (`150.00 EGP`): line prices, subtotal, discount, service, VAT, tender lines, paid, change (XORD-026). The price column grew from 140 to 190 dots.
- **Fixed** amounts did not line up on the decimal point on an Arabic receipt, and the currency code under the total sat under the middle of the figure (XORD-025). Amounts now share one right-aligned box in both languages; the code ends where the figure ends. Preview and print agree.
- **Fixed** (in the same pass) the printer settings form rebuilt its config from the printer name and paper width only, which would have reset any new setting on the next edit.
- Not changed: money arithmetic, rounding and tax; the ETA QR; XOrder appears only in the footer line `xorder.io`, as before (now pinned by a test).

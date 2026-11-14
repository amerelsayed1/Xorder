# Receipt: identical items from several rounds print as one line — technical plan (approved 2026-10-28 with the recommendations; implemented, uncommitted; see TEST_REPORT.md)
Status: implemented, uncommitted · 2026-10-29 · Spec: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section B2 (README XORDER-008 problem B; proposed id **XORD-038**) · Repo: `xorder-pos` only · Verified against `xorder-pos` branch `fix/pos-pin-keyboard` (= `main` `c67c754` + commit `edc37fd`; one unrelated uncommitted file `test/data/local_bootstrap_test.dart`). Work goes on a **new branch off `main`**.

## 1. Cause re-confirmed
- Sent lines never merge on the ticket, on purpose: `TicketEngine.addLine` merges only into draft lines "or the printed round and the bill stop agreeing" (`lib/domain/services/ticket_engine.dart:293-327`; key = `productId:sortedModifierIds`, `ticket.dart:239-244`).
- The receipt copies lines one for one: `ReceiptData.fromTicket` (`receipt_data.dart:134-143`) and `ReceiptData.fromOrder` for reprints (`:214-223`); `ReceiptDocument` prints each (`receipt_document.dart:346-355`).
- The slip prints per line only name, quantity and **gross** line total (`unitPrice × quantity`); discounts are printed as one figure, never per line. So merging for display changes no total.

## 2. Design: merge at presentation only
A pure function `ReceiptLine.consolidate(List<ReceiptLine>)` in `receipt_data.dart`, called by both factories. Nothing stored changes: `pos_order_lines`, rounds, line events, refunds, kitchen and history keep every row.
- `ReceiptLine` gains an optional `mergeKey` (String?). Built by the factories: live ticket = `line.key` + unit price (minor) + `note` + repriced flag; reprint = `OrderRecordLine.lineKey` + unit price + `note` (`order_record.dart:91-105`; the reprint has no repriced flag, so equal unit price is the test). A line with **no key never merges**.
- Merge rule: same `mergeKey`, same `isVoided == false`. Quantities add; line totals add as integers (exact, no rounding step). Name is the first line's. Order of the slip = order of first appearance.
- Never merged: voided lines (stay struck through, one row each, audit visible), lines with a different modifier set, unit price, note or repriced state, and **lines whose key carries a line-scope discount** (conservative reading of the README rule "do not merge if the applicable discount differs"; the slip does not show line discounts today, so this is only caution).
- Totals: subtotal, discount, service, VAT, total, paid, change are untouched; they come from the engine/ledger, not from the printed lines. A test asserts the sum of printed line totals equals the sum before merging.
- The comment in `receipt_document.dart` ("adds, subtracts and rounds nothing") stays true: the only addition is in `consolidate`, in integer minor units, and is tested.

## 3. Stages
| # | Stage | Files | Tests |
|---|---|---|---|
| 1 | `mergeKey` + `consolidate` (pure) | `lib/features/receipt/receipt_data.dart` | new `test/features/receipt_merge_test.dart`: rounds 1+1+2 of Mango Juice at 50.00 -> one line ×4 = 200.00; different modifiers / price / note / repriced state stay apart; voided never merges and does not merge into a live line; same-price repriced merges and keeps `*`; line-discount key not merged; no key never merges; order of first appearance; printed sum unchanged |
| 2 | Use it in both factories | same file | `receipt_document_test.dart`: live receipt from a 3-round ticket prints one `Mango Juice` row, qty 4, `200.00 EGP`; totals rows identical to the unmerged ones; reprint from three `OrderRecordLine`s with one `lineKey` prints the same; Arabic/English |
| 3 | Regression | existing receipt tests | `receipt_document_test`, `receipt_print_test`, `receipt_amounts_test`, `receipt_design_test`, `receipt_raster_test`, then whole `flutter test` |
Verification: `cd apps/xorder-pos && flutter analyze && flutter test test/features/receipt_merge_test.dart test/features/receipt_document_test.dart test/features/receipt_print_test.dart`, then the whole suite. Mutation check: make `consolidate` return its input and confirm the merge tests fail.

## 4. Scope boundaries (what is deliberately NOT changed)
- **Order history detail, refunds, void dialogs, the cart:** they act on individual `pos_order_lines` rows (a refund points at a line id); merging there would break them. Proposed: leave as is (open question 1).
- **Kitchen:** no kitchen print exists in the code; "send only the new quantity" is already how rounds work (`roundNumber` per line) and is not touched.
- Order number, PIN, dark toggle, dropdowns, user Code: other items.
- No schema, migration, API, cloud or contract change; no PostgreSQL test needed.

## 5. Impact and risk
Venue models: restaurants (rounds, open checks) benefit; cafés/food trucks (one round) see no change; cloud kitchens n/a. Risk: a customer who ordered the same dish in two rounds with a different note now sees them on separate lines (intended). Rollback: revert one commit; stored data untouched.

## 6. Approvals
None of the gated kinds (display only, no migration/order-state/contract change). **Needs your go.** Please also decide:
1. History order detail: keep every row (recommended, refunds need it) or merge there too?
2. Lines with a line-level discount: never merged (recommended) or merge anyway since the slip shows no line discounts?
3. Should the slip ever show round markers (R1/R2)? Recommended: no.

## 7. As built (2026-10-29)
Branch `fix/receipt-merge-rounds` (off `main` `c67c754`). One file changed in `lib/`: `lib/features/receipt/receipt_data.dart` (`ReceiptLine.mergeKey`, `ReceiptLine.consolidate`, both factories). Decisions taken as recommended: the history detail, refunds and the cart keep every row; a line whose key carries a line-scope discount never merges; no round markers on the slip. Tracker id **XORD-038**. Merge key, live ticket: `line.key|unit price (minor)|note|repriced`; reprint: `lineKey|unit price|note` (a reprint has no repriced flag, so the equal unit price is the test). Voided lines and lines with a line discount get no key and stand alone.

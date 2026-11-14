# Branch order number (shared by all tills) — shift-order-number
Status: **implemented, uncommitted, migration 63 not applied to any real database** · 2026-10-28 (revised same day) · Source: the owner's request, "Keep the invoice number as it is. MAIN-2026-000001 stays as the legal and tax number … keep this number in the db, and show the count of this client in the shift", then "number should be shared between all tills, not only for one device" (README XORDER-008, problem A; proposed id **XORD-036**) · Verified against: xorder-pos `c67c754` (one unrelated uncommitted test file), xorder-cloud `775bf0f` (read only). Investigation: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` §B1. The slug keeps the first name; the counter is no longer per shift.

## 1. Summary
Every order keeps its invoice number (`MAIN-2026-000001`) exactly as today. In addition each order gets a short **order number** (1, 2, 3 …) from **one counter shared by every till in the branch**, so two tills never show the same number at the same time. The counter starts again at 1 when a new business day opens (assumed; see 13). It is saved on the order and shown where the customer and kitchen need a simple number.

## 2. Why
The invoice number is long, belongs to the tax record and never resets, so nobody can call it out. Counter staff and kitchen need "order 17". With several tills feeding one kitchen, a number that repeats on a second till is useless, which is why the counter is shared. Helps cafés and food trucks most; restaurants and cloud kitchens with several tills benefit from the sharing.

## 3. Goal and success
A cashier at any till can say "order 17" and find it on screen, receipt, reprint and history; within a branch's business day the number is never repeated, even across tills; the invoice number is untouched.

## 4. Users, roles and permissions
Cashier sees it; manager/owner sees it in history. No new permission; nobody edits it. Cloud roles: not applicable (the cloud only stores it, see 10).

## 5. Today
- Invoice number: `formatInvoiceNumber` → `prefix-year-000042` (`lib/data/postgres/postgres_orders_repository.dart:455-460`) from `pos_invoice_sequences` keyed `(restaurant, branch, year)` with a row lock (`:402-450`, `migrations.dart:36`); unique per branch (`:52,68`). The cloud returns `server_invoice_number`, preferred by history (`postgres_order_history_repository.dart:81`).
- Orders are written **at settlement** (`submit`, `:72`) and when voided (`voidOrder`, `:200`); both take an invoice number. Kitchen rounds live on the ticket (`roundNumber`, `ticket.dart:186`) before any order row exists. Parked tickets are stored separately (`parked_ticket_codec.dart`).
- **Shifts are per terminal** (one open per terminal, `pos_shifts_one_open_per_terminal`, `migrations.dart:321-325`), so a shift cannot carry a shared counter.
- **A business day is per branch, shared by every till**: `pos_business_days`, unique `(restaurant_id, branch_id, business_date)` (`migrations.dart:1458-1473`). Orders are stamped with `business_day_id` by the database trigger `pos_stamp_business_day` (`:3253-3289`), choosing the day whose window contains the moment. This is the natural home for a shared counter.
- Latest POS migration: 62 (`:4768`); next is 63.
- Kitchen printing: **UNVERIFIED** (only a "round sent" toast found, `sale_screen.dart:524`). No KDS (known gap).
- Missing: the counter, the column, and every place that shows it.

## 6. Scope
In: the number, its storage, allocation, display on receipt (live and reprint), order detail, order history, sale screen header after settlement, and the kitchen round slip **if one exists**; offline and cloud tills.
Out: changing or reformatting the invoice number; merging identical items across rounds (XORDER-008 problem B); e-invoicing payloads; per-till or per-shift counters; reports by number; customer names.

## 7. Behavior and business rules
- **BR-1** Invoice number and its sequence are unchanged.
- **BR-2** Order number is a positive integer, no prefix or zero padding, +1 per order.
- **BR-3** One counter per **branch and business day**, shared by all tills of that branch. A new business day starts at 1.
- **BR-4** Once given it never changes; a round added to the same order keeps it; a replayed submit (same `client_transaction_id`) returns the same number and consumes none.
- **BR-5** Voided and cancelled orders keep their number; numbers are never reused.
- **BR-6** If there is no open business day, the order has no number (null, shown "—"); never invented.
- **BR-7** Allocation is safe when two tills write at the same instant (row lock, like the invoice sequence).

## 8. Acceptance criteria
- **AC-1** Given a business day just opened, when the first order is settled on till A, then its order number is 1 and the invoice number is the next in its sequence, unchanged. *(PostgreSQL repository test)*
- **AC-2** Given order 1 on till A, when till B settles an order, then it is 2. *(same, two terminals)*
- **AC-3** Given two tills settle at the same instant, then numbers are distinct and consecutive. *(PostgreSQL concurrency test)*
- **AC-4** Given the day is closed and the next opened, then the next order is 1 while the invoice number keeps counting. *(same)*
- **AC-5** Same ticket id submitted twice: one order, number not consumed twice. *(same)*
- **AC-6** A voided order keeps its number; the next order is not renumbered. *(same)*
- **AC-7** No open business day: number null; history shows "—"; the receipt **leaves the row off** (as built, to keep the paper clean). *(same + receipt widget test)*
- **AC-8** The number appears on receipt, reprint, order detail and history in en and ar, RTL intact, digits consistent with other references. *(receipt and widget tests; a person looks at the paper)*
- **AC-9** Migration 63 on a database with existing orders leaves old orders with a null number and changes nothing else. *(migration test on a throwaway database)*
- **AC-10** (as built) The cloud sync payload is **not changed** and nothing is sent to the cloud (owner decision: offline mode first). *(no new test; stated gap)*

## 9. Edge cases and failure modes
- **Cloud-mode tills:** each keeps its own local PostgreSQL (`deployment.dart`), so two cloud tills in one branch cannot share a count through a local row lock; sharing there needs the cloud to allocate it (see 10 and 13). Verified in source 2026-10-28.
- Offline branch server (all tills on one PostgreSQL): the lock works as for the invoice number.
- Pay-last restaurants: the order row is written at settlement, so rounds sent before payment have no number yet (see 13).
- Retry/idempotency: allocation in the order's own transaction, so a retry cannot skip or duplicate.
- Business day closing while a sale is in flight: the trigger's rule decides the day (existing behavior); the number follows that same day.
- Arabic UI digits: **UNVERIFIED** which the receipt uses. Tenant boundary: counter row carries restaurant and branch.

## 10. Impact
- **xorder-pos:** migration 63 (nullable column on `pos_orders`, a counter table keyed `(restaurant, branch, business_day)` with the row lock); `submit` and `voidOrder`; `ReceiptData` factories (`receipt_data.dart:129,205`); history queries and detail; sale header; one new label in `app_strings.dart` (en, ar). Additive.
- **xorder-cloud:** none for offline-mode branches (all tills share one PostgreSQL). For cloud-mode branches with several tills, only if the owner chooses cloud allocation (open question 1). Then a new additive contract item (`POS-BE-xxx`, not yet written, none invented) for the cloud to allocate the number; that would reach `xorder-cloud` `main` and auto-deploy, needing `/release-check`.
- Deploy: POS and cloud independent; the field is optional.
- Docs: `pos-orders` and `pos-receipts-printing` after the change; XORD-036 in the QA file on approval.

## 11. Dependencies, known gaps, risks
Depends on an open business day (`pos_business_days`). The number is **not unique across days or branches** and must never be used as an identifier. Migration on a large live `pos_orders` is an additive nullable column (PostgreSQL locks reviewed by reading only).

## 12. How it will be tested
PostgreSQL repository tests with `test/data/pg_fixture.dart` (AC-1 to 7, 9); receipt and history widget tests at 1440×900 in en and ar (AC-8); outbox unit test (AC-10). A person checks a printed receipt. Run `test/data/` order and business-day tests, receipt and history tests, then `scripts/check.sh`.

## 13. Decisions and open questions
**Decided 2026-10-28 (owner):**
- The invoice number is unchanged and kept in the database; a separate order count is added.
- The count is **shared by all tills** of the branch.
- It **resets every business day**.
- **Voided orders keep their number.**
- It is **given at payment**, together with the invoice number (so a kitchen slip printed before payment does not carry it).

**Verified 2026-10-28 (source, `lib/core/config/deployment.dart`):** in **offline** mode every till of a branch points at one PostgreSQL on the main device (`main_device` holds the database; `client_terminal` tills use it), so the row lock shares the count correctly. In **cloud** mode "terminals keep a local PostgreSQL of their own and sync it to the hosted platform", so two cloud tills in one branch have separate counters and **cannot share a number locally**. Shared numbering for cloud tills would need the cloud to allocate it (a new additive contract item, `POS-BE-xxx`, not yet written).

**Still open:**
1. **Cloud-mode branches with more than one till:** (a) ship offline mode first and leave cloud tills with their own per-till count, shown as such; (b) have the cloud allocate the number (contract change, cloud first, `/release-check`, and a till that is offline would still need a fallback). Recommended: (a) now, (b) as a separate item. Needs the owner's call.
2. Kitchen slip: show the number only if a kitchen print exists (to verify when implementing).
3. Arabic or Western digits on the receipt (to verify).

Next: `/implement shift-order-number`. It will need approved: migration 63 (written, not applied to any real database); an order-write change; answer to open question 1. Cloud change only if 1(b) is chosen.

## 14. As built (2026-10-28)
Implemented as designed in `TECHNICAL.md`, with these differences from the text above: the receipt row is omitted rather than printed as "—" when there is no number; the cloud payload is untouched; the sale screen shows the number through the receipt that opens after payment (no separate widget); the order detail shows "Order no. 17" in its info line; the history list has a new narrow `#` column. Arabic label «رقم الطلب اليومي» and English "Order no." are my wording: **needs the owner's read**. See `TEST_REPORT.md` for what was and was not proven.

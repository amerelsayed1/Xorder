# Branch order number — changelog
## 2026-10-28 (unreleased, uncommitted)
- Added: migration 63 (counter table, `pos_orders.day_order_number`, trigger, grant); the number is returned by `submit`/`voidOrder`, kept on `OrderRecord`, printed on the receipt ("Order no." / «رقم الطلب اليومي», left off when none), shown in order history (new `#` column, "—" when none) and the opened order's detail line.
- Unchanged by decision: invoice number, cloud sync payload, kitchen slip (none exists).
- Scope decision: shared by all tills of an **offline** branch (one PostgreSQL); cloud-mode tills each have their own database and count separately until a later item.

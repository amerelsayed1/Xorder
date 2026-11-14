# Branch order number — test plan (criterion -> test)
| AC | Test | Kind |
|---|---|---|
| AC-1 first = 1, invoice unchanged | `test/data/day_order_number_test.dart` "the first order of a day…", "the invoice number is whatever the writer gave…", repository "two tills…" | PostgreSQL |
| AC-2 shared by tills | same file "every till of the branch draws from the same count" | PostgreSQL |
| AC-3 simultaneous tills | same file "two tills settling at the same instant…" (12 concurrent inserts) | PostgreSQL |
| AC-4 next day restarts | "the next trading day starts again at 1" | PostgreSQL |
| AC-5 replay | repository "a replay returns the same number and spends none" | PostgreSQL |
| AC-6 void keeps number | "a voided order keeps its number…" and repository "a voided order keeps a number…" | PostgreSQL |
| AC-7 no open day -> none | "with no trading day open…" (SQL) and repository "…carries no number" | PostgreSQL |
| AC-8 shown | `receipt_document_test.dart` group "the order number" (en, ar, none, reprint); `order_history_test.dart` list column, "—", opened order | widget/unit |
| AC-9 migration, old rows NULL | "orders that existed before migration 63 keep a null number" | PostgreSQL |
| AC-10 payload unchanged | no code change in `_enqueueForSync`; **no new test** (existing outbox suites run unchanged) | gap, stated |
| Grants (trigger runs as the till) | `till_grants_enforced_test.dart` "a sale takes the trading day's order number as the till…"; `till_grants_test.dart`; `grants_cover_usage_test.dart` | PostgreSQL / unit |
| Trigger order | "the number trigger runs after the one that picks the day" | PostgreSQL |
Needs a person: a printed receipt (paper, Arabic digits and label), the sale screen after payment, the history list at narrow widths, a two-till branch server.

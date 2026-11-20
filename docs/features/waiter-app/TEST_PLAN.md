# Test plan — waiter-app (WA1)

| Suite | What it proves |
|---|---|
| `packages/xorder_waiter_link/test/waiter_link_test.dart` | over a real loopback socket: hello; nothing without a device token; one code pairs one device once; expired code; code guessing locked out; PIN sign-in, wrong PIN lockout and recovery; `pos.operate` required; menu/floor need a session; idle session expiry; revoked device; ops applied, conflict returns the current check, refusal reason, unknown table; wire round trips; money without doubles; unknown enum falls back |
| `packages/shared_module/test/features/waiter_link/till_waiter_backend_test.dart` | the real `TicketEngine` behind the link: menu (open-price excluded, selling price, groups); sign-in capabilities, inactive staff refused; floor states and totals; first item seats the table priced exactly as the sale screen; send round / nothing to send; required options, unknown option/product, bad quantity; all-or-none; cancel needs `order.item.delete_before_send` and is recorded; sent lines untouchable; quantity to 0 = cancel; notes, guests; emptied new check seats nobody; stale version, seated-while-free, lost race → conflict; payment started → refused |
| `packages/shared_module/test/data/waiter_devices_test.dart` (integration; PostgreSQL and SQLite) | token found, only the hash stored; distinct tokens; newest first; revoke keeps the row and first date; last seen; another business's token opens nothing; blank name refused |
| `packages/shared_module/test/features/waiter_link/waiter_link_end_to_end_test.dart` (integration; PostgreSQL and SQLite) | client → socket → link server in a real till provider graph → engine → versioned store; the till's floor sees the waiter's round at the same total; a stale handheld edit after the cashier changed the table is a conflict showing the cashier's change; revoke shuts the device out at once |
| `apps/xorder_pos_waiter/test/waiter_flow_test.dart` | phone (390×844, Arabic): pair, PIN, floor, add, check tab, send → round 1; tablet (800×1280, English): side-by-side, options sheet with a required group; conflict message and latest check; wrong PIN worded; revoked → back to pairing, token forgotten |
| `packages/shared_module/test/features/waiter_link/waiter_theme_parity_test.dart` | the handheld's colours (read from its `theme.dart` as text) equal the till's light palette — on the till's side so the handheld needs no dependency on the till, not even a dev one |
| `apps/xorder_pos_waiter/test/package_boundaries_test.dart` | nothing under the handheld's `lib/` imports the till or either till app |

Not covered (needs a person or a device): real Android/iOS phones and tablets, Arabic layout on small screens, restaurant Wi-Fi, the till's Settings › Waiter devices dialog by eye.

## Floor 500 fix (2026-11-18)
| Criterion | Test |
|---|---|
| AC-F1 open bill request with NULL table does not break the floor | `WaiterWireTest::test_an_open_bill_request_with_no_table_does_not_break_the_floor` |
| AC-F2 floor loads after a table with an open request is deleted | `WaiterWireTest::test_the_floor_loads_after_a_table_with_an_open_bill_request_is_deleted` |
| AC-F3 open request still marks `bill_asked` | `WaiterWireTest::test_a_table_with_an_open_bill_request_is_marked_bill_asked` |
| AC-F4 closed / other tenant's requests never mark a table | `WaiterWireTest::test_closed_and_other_restaurants_bill_requests_do_not_mark_a_table` |
| S2 delete cancels open requests, read alerts, other tenant untouched | `TableTest::test_deleting_a_table_cancels_its_open_bill_requests` |
| S2 bulk delete, table with orders spared | `TableTest::test_bulk_delete_cancels_open_bill_requests_and_spares_tables_with_orders` |
| S2 refused delete keeps the request | `TableTest::test_a_table_with_orders_that_cannot_be_deleted_keeps_its_open_bill_request` |
| S2b area delete cancels its tables' open requests, other areas untouched | `DiningAreaTest::test_deleting_an_area_cancels_the_open_bill_requests_of_its_tables` |
| S2b area with orders refused keeps the request | `DiningAreaTest::test_an_area_with_history_that_cannot_be_deleted_keeps_its_open_bill_requests` |
Gaps: no test that a failing delete rolls the cancellation back; branch delete is not covered (known gap, TECHNICAL §15); PostgreSQL not exercised (JSON `data->bill_request_id` comparison read, not run).

# Guest paging — test plan

Planned coverage per acceptance criterion (`FEATURE.md` §8). Executed results live in `TEST_REPORT.md` only.

| AC | Stage | Test (file :: method) | Kind |
|---|---|---|---|
| AC-1 feature off → 403 / no token | S1 (+S2) | `tests/Feature/GuestPagingTest::test_board_and_pickup_are_forbidden_without_the_feature`, `::test_guest_paging_is_sold_not_inherited`; S2 adds the public 403 and the no-token create | PHPUnit |
| AC-2 QR order gets token/tracking_url by type | S2 | `GuestPagingTest::test_a_qr_pickup_order_gets_a_tracking_token_only_when_the_flag_is_on`, `::test_only_paged_order_types_get_a_token`, `::test_a_round_of_a_seated_table_is_never_paged` | PHPUnit |
| AC-3 public track payload, 404s, 304 | S2 | `GuestPagingTest::test_tracking_shows_the_reference_and_state_and_nothing_private`, `::test_tracking_answers_404_for_unknown_expired_or_malformed_tokens_and_403_when_off`, `::test_tracking_is_304_when_nothing_moved_and_reflects_cancellation`, `::test_tracking_localises_the_restaurant_name` | PHPUnit |
| BR-7 follow / ack / call-out; push token | S2 | `GuestPagingTest::test_follow_and_ack_stamp_once_and_ack_needs_ready`, `::test_push_token_can_be_stored_and_removed` | PHPUnit |
| AC-4 READY once, PICKED_UP, backwards 422, cross-tenant 404, no orders.update 403 | S1 | `GuestPagingTest::test_ready_stamps_once_and_replay_is_a_no_op`, `::test_picked_up_follows_ready_and_completes_a_new_order`, `::test_pickup_never_moves_backwards`, `::test_pickup_rejects_unknown_values_and_unpaged_orders`, `::test_pickup_is_tenant_scoped_and_capability_gated` | PHPUnit |
| AC-5 call_out after N minutes, ack clears it | S1 + S2 | `GuestPagingTest::test_board_lists_todays_paged_orders_and_computes_call_out`, `::test_follow_and_ack_stamp_once_and_ack_needs_ready` | PHPUnit, `Carbon::setTestNow` |
| AC-6 POS sale with pickup_token replay | S5 | `tests/Feature/Pos/PosPickupTest` (planned) | PHPUnit |
| AC-7 delayed POS READY after PICKED_UP, clamp, unknown 422 | S5 (service rule S1) | `GuestPagingTest::test_a_supplied_event_time_is_clamped_to_the_orders_life` (service); endpoint in S5 | PHPUnit |
| AC-8 bootstrap menu_url + features | S5 | planned | PHPUnit |
| AC-9 POS token + receipt QR + outbox fields | S6 | planned POS tests | Flutter |
| AC-10 POS Ready, outbox event, drain rules | S7 | planned POS tests | Flutter |
| AC-11 till grant | S6 | planned | Flutter PG |
| AC-12 tracking page rings, RTL, review button | S3 | a person (in-app browser, mobile preset, en + ar) | manual |
| AC-13 push delivery / dead token pruning | S8 | pruning: PHPUnit with fake Messaging; delivery: a person | mixed |
| AC-14 prep-time report | S9 | `ReportTest` cases (planned) | PHPUnit |
| AC-15 migration additive | S1 | reviewed by reading + `/release-check` before push | review |
| BR-8 COMPLETED from the queue → PICKED_UP; CANCELLED leaves pickup alone | S1 | `GuestPagingTest::test_completing_a_paged_order_from_the_queue_marks_it_picked_up`, `::test_cancelling_leaves_the_pickup_fields_alone` | PHPUnit |
| Board: branch filter, ETag 304, tenant scope | S1 | `GuestPagingTest::test_board_filters_by_branch_and_answers_304_when_unchanged`, `::test_board_is_tenant_scoped` | PHPUnit |
| Resource shape: new keys present, no token in dashboard output | S1 | `GuestPagingTest::test_ready_stamps_once_and_replay_is_a_no_op` (`assertJsonStructure` + missing `pickup_token`/`pickup_push_token`), board test | PHPUnit |
| BR-2 eligibility helpers | S1 | `GuestPagingTest::test_eligibility_follows_the_flag_and_the_paged_types` | PHPUnit |
| D-6 cancelled order refuses Ready / Picked up | S1 | `GuestPagingTest::test_a_cancelled_order_is_never_paged_forward` | PHPUnit |

Gaps after S1: everything marked planned; the board page and the tracking page have no automated UI test (no JS test framework exists; none is added).

# Test report — waiter-app WA1 (2026-11-09)

Source: xorder-pos `development` on `6a5ceda` + uncommitted WA1 work. Local PostgreSQL 127.0.0.1:5432; test databases dropped by the script.

| Command | Result |
|---|---|
| `cd packages/xorder_waiter_link && flutter test` | 19 passed |
| `cd packages/shared_module && flutter test test/features/waiter_link/till_waiter_backend_test.dart` | 17 passed |
| `POS_PG_HOST=127.0.0.1 POS_PG_USER=$USER flutter test test/data/waiter_devices_test.dart` | 6 passed |
| `POS_TEST_ENGINE=sqlite flutter test test/data/waiter_devices_test.dart` | 6 passed |
| `POS_TEST_ENGINE=sqlite flutter test test/features/waiter_link/waiter_link_end_to_end_test.dart` | 3 passed |
| `flutter test test/features/waiter_link/waiter_theme_parity_test.dart` | 1 passed |
| `cd apps/xorder_pos_waiter && flutter test` | 5 passed (4 flow + boundaries) |
| **`scripts/check.sh`** (first run) | shared unit pass `+2640 ~2 -2`: `sqlite_schema_test` (expected no SQLite upgrade to run) and `grants_cover_usage_test` (new repository unclassified) — both test lists updated, see below |
| **`scripts/check.sh`** (second run) | **exit 0.** shared: analyze clean, unit 2642 passed (2 skipped), PostgreSQL 1145 passed (1 skipped, incl. the end-to-end and device suites); test_support analyze clean; offline 852 + 6; cloud 133 + 107; `xorder_waiter_link` 19; `xorder_pos_waiter` 5; SQLite pass 419 (16 skipped) + cloud 181 (8 skipped) |
| `flutter build macos --debug` (waiter app) | built; the macOS target was removed afterwards at the owner's request (2026-11-09), the app is Android/iOS only |
| `flutter build apk --debug` (waiter app) | built (`app-debug.apk`) |

Fixes made after the first run: `sqlite_schema_test` now expects a new file to record every migration (baseline + `sqliteUpgrades`); `grants_cover_usage_test` classifies `postgres_waiter_devices.dart` as a till repository.

After the second run started, the theme parity test moved from the waiter app into `shared_module` (so the handheld has no dev dependency on the till, whose plugins a debug build would register); it was run on its own (1 passed) and the waiter app re-tested (5 passed). The second `check.sh` did not include that one file.

Not run: the app on a real Android or iOS phone/tablet; the till's Settings › Waiter devices dialog by eye; a pairing between the real cloud/offline till and the handheld on a real LAN; release builds (signing is the owner's).


## 2026-11-09 — POS-BE-033 cloud half

Environment: macOS, PHP CLI, SQLite `:memory:`, Flutter on macOS. Nothing run against PostgreSQL or any real database; no migration applied outside the test database.

| Command (from the repo noted) | Result |
|---|---|
| `cd apps/xorder-cloud/apps/api && php artisan test --filter WaiterWireTest` | passed: 31 tests, 179 assertions |
| `php -d memory_limit=2G vendor/bin/phpunit --no-progress` (whole cloud suite) | 1222 tests, 1220 passed, **2 failed**: `GuestPagingTest::test_ready_stamps_once_and_replay_is_a_no_op` and `::test_follow_and_ack_stamp_once_and_ack_needs_ready` (fixed-date assertions, `2026-11-02` vs today; nothing on the waiter paths; **not baselined**: not re-run on a clean tree) |
| `php artisan test` (plain) | **crashes** with PHP's 128 MB memory limit in `routes/api.php` (the child process ignores `-d memory_limit`); not caused by a test failing, but not proven unrelated to the route additions either |
| `cd apps/xorder-pos/apps/xorder_pos_waiter && flutter analyze` | No issues found |
| `flutter test` (waiter app) | 14 passed, **2 failed**: both expect the device name `mona · linux` and get `mona · macos` (the test hard-codes the platform; the cloud tests, including the new URL assertion, pass) |

Covered by `WaiterWireTest`: hello/unknown slug/feature gate; first sign-in registers and returns the token once (stored hashed); one error for wrong PIN and unknown user; lockout after 5; no `pos.operate`; no PIN set; device and session depth; revoked device; 12 h idle; sign-out; **tenant boundary** (tokens, tables and products of another restaurant, dashboard list and revoke); menu prices; floor states; server-side pricing ignoring client prices; merge; qty/note/guests/remove; stale version 409 with no change; all-or-none batch; unavailable product and bad quantity; unknown op and empty batch; send creates the round, a second round appends to the same order, a repeated send is never a second round; sent lines not editable and keep their price; `PosPin::verify`.

Not tested / listed for a person: real concurrency on PostgreSQL (two phones, `lockForUpdate`); a real handheld against a deployed server; the push on `send` (best-effort, after the response); a restaurant with variants, required option groups or auto-applied groups (only plain products are in the fixtures); tax and service rules (the test branch has none); the Arabic strings in the dashboard error.

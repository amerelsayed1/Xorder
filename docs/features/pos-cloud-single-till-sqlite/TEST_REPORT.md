# Test report — pos-cloud-single-till-sqlite

Date: 2026-11-09 · macOS, Flutter 3.47.7, local PostgreSQL 127.0.0.1:5432 · xorder-pos `development` `13d5d06` (stages 0–7, not pushed).

## `scripts/check.sh` — exit 0, test database dropped
| Package | Analyze | Unit | PostgreSQL | SQLite (`POS_TEST_ENGINE=sqlite`) |
|---|---|---|---|---|
| packages/shared_module | No issues | +2622 ~2 | +1136 ~1 | +413 ~16 |
| packages/xorder_pos_test_support | No issues | — | — | — |
| apps/xorder_pos_offline | No issues | +852 (unchanged) | +6 | — |
| apps/xorder_pos_cloud | No issues | +133 | +107 | +181 ~8 |

The SQLite skips (24) are tests that need PostgreSQL itself, each naming why: login roles, migration replays, disabled triggers, the deferred constraint trigger (on SQLite the refunds repository checks it), the offline back office's tender writer.

Every stage also ran its own full `check.sh` or unit suites before commit (see TECHNICAL.md › Progress).

## Not run
- The Windows installer workflow (manual, on a Windows runner).
- `apps/xorder_pos_cloud/integration_test` (needs a local API, an owner account and a cloud-only licence).
- A large-history timing on SQLite (engine on the main isolate; follow-up).
- A power cut on a real laptop (AC-4 is covered by a reopen-after-failure test, not by pulling power).

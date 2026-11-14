# Test execution report: POS business day

## Date and environment
2026-10-24 · macOS · Flutter 3.47.7 / Dart 3.13.5 · `apps/xorder-pos` on branch `fix/offline-audit-2026-10-24` at `f78bfa7` **plus the uncommitted business-day change** · no database (`POS_PG_HOST` unset).

## Commands executed
- `flutter analyze`
- `env -u POS_PG_HOST flutter test test/domain/business_day_service_test.dart test/features/business_day_opening_ui_test.dart test/features/business_day_providers_test.dart`
- `env -u POS_PG_HOST flutter test --reporter expanded` (whole no-database suite)
- Red checks: each wiring change reverted in turn and the matching tests re-run; the provider guard changed to `rethrow` and its test re-run.

## Results (passed / failed / blocked / not run)
| Check | Result |
| --- | --- |
| `flutter analyze` | **No issues found** |
| New tests (domain 14, UI 10, providers 3) | **27 passed** |
| Whole no-database suite | **2701 passed, 70 skipped, exit 0** (181 s). Before this change: 2674 passed / 69 skipped; delta = +27 new tests, +1 skip (the new PostgreSQL file self-skips) |
| Red check: shift dialog wiring reverted | 3 of the shift-opening tests failed |
| Red check: lock-screen wiring reverted | the lock-screen resume test failed |
| Red check: provider guard made to rethrow | *nothing inside the glue can throw into the shift dialog* failed |
| `test/data/business_day_opening_test.dart` (6 PostgreSQL tests) | **NOT RUN** (compiles, analyzes clean, self-skips without `POS_PG_HOST`) |
| Manual walk on a throwaway database | **NOT DONE** |
| Independent review (fresh `code-reviewer`) | No blockers; 3 should-fix items (stale migration reference, unguarded glue, untested real providers) **fixed**; nits listed below |

## Evidence and logs (redacted)
First full run after the change failed one existing test, `theme_screens_test` ("the start screen paints from the palette it is given"): a pending timer from an `autoDispose` provider. Fixed by making `dayNoticeProvider` a plain provider like `businessDayProvider`; the rerun passed.

## Known gaps and release risks
- PostgreSQL behaviour (index race, trigger filing, closed-date refusal) is **unproven**: the shared development server lost databases for a reason not established (see the 2026-10-24 report, section 8) and was not used.
- Review nits left open: the notice captures `DateTime.now()` once (stale across 06:00 until invalidated); no test for orders and refunds being filed (relies on existing migration tests); import order in `start_screen.dart`; one `debugPrint` per sign-in on an unconfigured till.
- First real use of day close, backup on close and the restore guard may expose latent bugs.
- The one-time under-reporting on the first day after upgrade (a shift open at install, sales before the day's `opened_at`) was not put to the owner as a question; it is documented in FEATURE.md.

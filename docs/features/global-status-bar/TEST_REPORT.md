# Test report — global-status-bar
Run 2026-10-26 · macOS (Darwin 25.6.0) · Flutter widget tests, no database · xorder-pos `a6f5fe5` + a large uncommitted working tree that is not this feature's.

| Command | Result |
|---|---|
| Baseline, before any edit: `flutter analyze && flutter test` | analyze: `No issues found!`; tests: `+3249 ~79: All tests passed!` |
| After the build: `flutter analyze && flutter test` (full) | analyze: `No issues found! (ran in 58.6s)`; tests: `+3269 ~79: All tests passed!` |
| Final targeted: `flutter test` on `till_status_bar_test`, `back_office_shell_test`, `admin_entry_test`, `settings_bar_test`, `payment_keyboard_test`, `payment_after_entry_test`, `payment_reference_digits_test`, `sale_flow_test` | `+111: All tests passed!` |
| Final `flutter analyze` | **1 error, not from this feature**: `admin_messages.dart:352` `non_exhaustive_switch_expression` — `AccountRefused` was added to `admin_repositories.dart:251` by other work in the tree after the full run, and the switch does not handle it yet. |

Not run: `scripts/check.sh` (PostgreSQL-backed suites; the `~79` skipped tests are those), the app itself on macOS or Windows.

## Matrix (AC → result)
| AC | Test | Result |
|---|---|---|
| AC-1 | `till_status_bar_test` "every screen of a set-up till has it" (Start, Lock, Orders, Licence, Sale) | pass |
| AC-2 | "the welcome screen and the wizard do not" | pass |
| AC-3 | "the person: shown where somebody is in, hidden on Start and Lock…" | pass |
| AC-4 | "inside the back office it names the administrator, once" | pass |
| AC-5 | "the sale screen says the connection and the branch once" | pass |
| AC-6 | `back_office_shell_test` Home test and the pane walk assert no `till-status-bar` in Management's own tree; the one-bar-in-the-app case is AC-4's test | pass |
| AC-7 | "a cloud till shows the sync state, not the branch server" | pass |
| AC-8 | "in Arabic…", "long names ellipsize at the smallest window instead of overflowing" | pass |
| AC-9 | "the sale screen still fits the smallest window with the bar" (en, ar, 1024×700) | pass — proves it builds without an overflow error, not that it looks right |
| AC-10 | none | **not tested** — needs a person (a modal over a screen; idle lock) |

## Gaps and caveats
- Floor was not in the route loop (the fake till has no seating configured, so the router sends it to Sale). Its layout loses the same 44 px and has not been looked at.
- No test was mutation-checked for this feature (unlike the payment-screen ones); the AC-5 test depends on the sale top bar's pill and `branch · terminal` being gone, and would fail on the pill.
- Nothing was looked at in the running app: height, spacing, dark mode, and the bar beside the native menu bar on Windows are unseen.
- The full-suite run started before the AC-4 test was added; that test passed in the targeted runs.

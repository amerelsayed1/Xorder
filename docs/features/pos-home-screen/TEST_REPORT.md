# Test report — pos-home-screen
Run 2026-10-26 · macOS (Darwin 25.6.0) · Flutter widget and router tests, no database · xorder-pos `a6f5fe5` + a large uncommitted working tree (not this feature's alone).

| Command | Result |
|---|---|
| Baseline before any edit: `flutter analyze` and `flutter test` on `sale_flow`, `sign_in`, `idle_lock`, `order_type_rules`, `till_status_bar`, `start_gate` | analyze: `No issues found!`; tests: `+80: All tests passed!` |
| `flutter test test/features/home_screen_test.dart` | `+7: All tests passed!` |
| `flutter test test/features/home_flow_test.dart` | `+8: All tests passed!` |
| Mutation: skip-Home decision forced to "always Home" | 2 tests failed (one unseated type, one seated type); restored, `+8` pass |
| Mutation: Home removed from `needsSignIn` | `home_flow_test` "…nobody signed in is the lock screen" and `sign_in_test` "selling with a shift open and nobody signed in" failed; restored |
| Related suites together (`home_flow`, `home_screen`, `sign_in`, `idle_lock`, `start_gate`, `sale_flow`) | `+73: All tests passed!` |
| `flutter analyze` (whole project) | `No issues found!` |
| Full `flutter test` | `+3345 ~81: All tests passed!` (the last full run before this feature was `+3329 ~81`) |

## Matrix
| AC | Result |
|---|---|
| AC-1 | pass (`home_screen_test`: seeded four with chips, Arabic names, configured names and order) |
| AC-2 | pass (configuration changed under the mounted screen) |
| AC-3 | pass, mutation-checked, on the route history of the real app |
| AC-4 | pass (tap → floor; floor Back → Home; with one type, Back → Start) |
| AC-5 | pass (`ticket.orderType` takeaway, `tableId` null) |
| AC-6 | pass (redirect, `needsSignIn`, idle lock at five minutes) |
| AC-7 | pass as "no overflow at 1024×700 in Arabic"; not a look at it |
| AC-8 | **not tested separately**: a cloud till and an offline till use the same providers, but no test builds one of each |
| AC-9 | pass (the six related suites, then the full suite) |
| AC-10 | **not done: needs a person** |

## A defect the tests found
Start read the order types before anything had loaded them, saw the seeded four, and sent a one-type branch to Home, where the screen's own safety net forwarded it. The final route looked right, so only a test on the **route history** showed it. Fixed: Start warms the configuration and branches while the shift opens, and `afterShift` waits for both before deciding.

## Gaps and caveats
- Nothing was looked at in the running till: spacing, the four-button column on a counter screen, dark theme, and Arabic reading order are unseen.
- The number keys work by character first and by key as a fallback; as with the payment screen, an Arabic-layout key event cannot be sent into the widget in the harness, so that path is not proven.
- A cloud till's order types arrive differently from an offline till's (not traced, **UNVERIFIED**); the tests override the provider.
- No way back to Home from the sale screen (owner's decision), so after the first sale a cashier changes type with the top bar's switch.
- The suite ran for 42 minutes on a busy machine; the result is the same suite as before plus 16 tests.

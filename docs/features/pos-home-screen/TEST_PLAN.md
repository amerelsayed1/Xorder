# Test plan — pos-home-screen
Planned 2026-10-26. Executed results in `TEST_REPORT.md`. Flutter widget and router tests in `apps/xorder-pos/test/features/`; no cloud, database or printer.

| AC | Proof | Test |
|---|---|---|
| AC-1 one button per enabled type, in order, configured names (en/ar) | four seeded types in order with number chips; Arabic names; names and order taken from the back office's configuration | `home_screen_test` (first three) |
| AC-2 a disabled type has no button; re-enabling shows it without a restart | the configuration changed under the mounted screen | `home_screen_test` "a type turned off…" |
| AC-3 one enabled type skips Home | the route history of the real app never contains `/home` (unseated → sale with that type; seated → floor, whose Back is Start); mutation-checked | `home_flow_test` "one unseated type", "one seated type" |
| AC-4 a seated type opens the floor | tap → `/floor`; Back from the floor → Home | `home_flow_test` |
| AC-5 an unseated type starts a sale of that type, no table | `ticket.orderType` and `tableId` after the tap | `home_flow_test` |
| AC-6 Home with a shift open and nobody in is Lock | router redirect; `needsSignIn` for Home in all three states; the idle lock locks Home at five minutes | `home_flow_test`, `sign_in_test`, `idle_lock_test` |
| AC-7 Arabic, no overflow at 1024×700 | four types in Arabic at the smallest window | `home_screen_test` |
| AC-8 cloud and offline | **gap**: both read the same provider; no separate cloud-till test was written (see report) | — |
| AC-9 existing flows unchanged | `start_gate_test`, `sale_flow_test`, `sign_in_test`, `idle_lock_test`, `till_status_bar_test`, then the full suite | existing |
| AC-10 look and feel with real names and four types | **needs a person** | manual |

Also covered: keys 1–4 and the numpad choose a button (`home_screen_test`); a loading configuration shows a wait and no buttons; a single-type list forwards once and never shows a lone button; two types with nothing seated go to Home, not the floor.

Edited on purpose: `sign_in_test` (Home added to the guard's three cases), `idle_lock_test` (Home in its route list and a new test).

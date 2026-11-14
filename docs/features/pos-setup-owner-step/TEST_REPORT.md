# Test report — pos-setup-owner-step

Date 2026-10-27 · Environment: macOS, Flutter widget and unit tests with fakes (no database), xorder-pos `5cf13cc` + uncommitted work (this feature's and unrelated, see TECHNICAL §8). Planned tests: `TEST_PLAN.md`.

## Commands and results (real output, abridged)
| Command | Result |
|---|---|
| `flutter test` before this change (after the sign-in work) | `+3438 ~81: All other tests passed!`, exit 0 |
| `flutter test`, first full run after stages S1 to S5 | `+3471 ~81 -1`: `setup_typing_test: a PIN keeps every digit that was typed` (it looked for the PIN on the first screen; it is on the owner's screen now) — test updated |
| Independent review (read-only code-reviewer) | 1 high (hidden: the PostgreSQL-tagged `installer_owner_test` supplies no PIN confirmation), 1 medium (an empty administrator password became impossible), 2 low wording items, a busy guard, test gaps. All fixed except the "known and left alone" items in FEATURE §14 |
| `flutter analyze` (final) | `No issues found!` |
| **`flutter test`** (final, whole suite, after the review fixes) | **`+3479 ~81: All other tests passed!`, exit 0** (0 failures; the 81 skipped are the `integration`-tagged PostgreSQL suites, which self-skip without `POS_PG_HOST`) |
| `bash scripts/harness/verify.sh` | no `pos-setup-owner-step` problems (the 3 reported are in other features' docs) |

## Tests added or changed
New: `setup_owner_step_test.dart` (controller: footer rule, Back, arriving, PIN twice, failure routing, busy guard; 14 cases), `setup_owner_step_ui_test.dart` (widget: both screens, Show/Hide, counter, mismatch, failure return, done card, words in EN and AR, 1024×700 Arabic; 19 cases). Changed: `setup_wizard_test.dart` (one test), `setup_typing_test.dart`, `localisation_test.dart` (string map), `data/installer_owner_test.dart` (PostgreSQL-tagged).
Mutation checks (the test fails without the behaviour): the PIN-mismatch rule; the failure routing to screen A; the Show/Hide toggle.

## Not run, or not provable here (said plainly)
- **`scripts/check.sh` and every PostgreSQL-tagged suite**, including `installer_owner_test` (AC-10): not run. The real database build, its success path and `ownerAlreadyExists` are proven by nothing in this run.
- **A person on a real till**: the whole step in Arabic at 1024×700, the Show/Hide feel, keyboard flow. The Arabic wording of the 15 new strings and the 2 reworded ones needs a native reader.
- **A live wrong-password refusal** (`auth`): the routing is proved by a table over every `PosDbFailure`, the live case only for a refused connection.
- **Cloud**: not touched, not tested.

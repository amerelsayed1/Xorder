# Round 8 validation report: `pos-shifts` core

Date: 2026-10-20 · Command: `validate pos-shifts` (core only; focus: the round-7 edit set and the citations expanded from shorthand; `BEHAVIORAL_ANALYSIS.md` excluded) · Repos: cloud `main 06bc8e3`, POS `main d592db8`
Freshness before validating: both HEADs unchanged, 0 committed changes since the documented revisions, the same uncommitted files (10 cloud, 11 POS). Mechanical checks: `check-docs.py` passes; 218 line-level citations resolve, 0 problems, 0 shorthand citations.
Validator: a fresh `feature-analyst` agent that did not read `docs/validation/`; about 150 tool calls, roughly 290k tokens. The author verified every finding against source before acting.

## Result
Reviewer verdict: **core has 3 wrong/stale statements** (one of them a judgement call). Core passes so far: 4, 2, 3 errors. The reviewer reported 283 prefixed citations resolving with 0 missing or out-of-range, about 200 opened for meaning and found correct, all route/middleware/validation/error-code/schema/permission/absence claims correct, and nothing in the core restating the analysis except two ordering sentences. No statement about what the system does at a single location was found false; the three errors are a test attributed to the wrong pane, a citation range pointing at the `shift.open` dialog for a `shift.close` prompt, and an omission (the closed dialog's subtitle shows the variance to people who cannot view it). Because wrong statements were found, the core is **not promoted**.

## Findings and disposition (all author-verified, all fixed)
| # | Severity | Finding | Source evidence | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | the over/short mask test (`shift_history_panes_test.dart:475-498`) belongs to the Finance › Settlements pane, not People › Shifts; no test covers the Shifts pane mask | `P:test/features/shift_history_panes_test.dart:411,475-480` | FEATURE and TEST_PLAN corrected, gap added |
| W2 | wrong | `shift_dialogs.dart:84-103` is the `shift.open` dialog; the `shift.close` prompts are at `:341-347` and `:375-384` | `P:lib/features/shift/presentation/shift_dialogs.dart` | citations split |
| W3 | misleading by omission | the closed dialog's subtitle states balanced / the variance to everyone, although the Z report is masked | `shift_dialogs.dart:576-579` | added to Actors, cash policy and TEST_PLAN gap |
| M1-M5 | missing | licence gate on opening (`start_screen.dart:71-72`); bootstrap `pos.shift_required` with no reader; `TenantContext::overrideId` in the device middleware; history list shows expected/counted cash to everyone; heartbeat/bootstrap fields | `C:app/Http/Middleware/PosDeviceAuth.php:77`; `C:app/Services/PosBootstrapService.php:147` | added |
| B1-B2 | belongs in analysis | WF-3/WF-4 stated the close "after orders and movements" and a complete per-run sequence | | reworded to phase order with pointers |
| U1-U3 | unverifiable | "older tills without a user id still sync" (no such tills found); throttle bucket not read; pass counts in headers | | reworded to facts / marked untested |
| S1-S8 | style | terminal-delete tests described precisely (`TenantCreationTest.php:347`, comment `:388-392` as intent); `postgres_shift_repository.dart:350-360` for the `require` call; `migrations.dart:2228` vs `:2203`; `cloud_refunds_test.dart:552-579` is a server-reply quarantine; dangling range; inventory gap list; bare-filename continuation citations in prose | | fixed (bare-filename continuations left; they follow a full path in the same row) |

## Not checked
`BEHAVIORAL_ANALYSIS.md` (by design); `docs/validation/*` (so the history counts in headers could not be checked by the reviewer; they are maintained by the author); runtime behavior (nothing executed); `cash_dialogs_test`, `cash_movement_test`, `drawer_open_flow_test` bodies; i18n strings.

## Status decision and what the series shows
**`drafted`**: promotion requires a pass that finds nothing wrong. Eight validation passes have been run (combined document: 6, 7, 4, 3, 5 behavioral errors; core only: 4, 2, 3). Each pass, run by a fresh reviewer with a larger and different set of checks, finds a small number of new defects, mostly in test attributions, citation ranges and omissions, and none that reverses what a single code location does. This is the expected behavior of an independent reviewer on a ~170-line, ~280-citation document: zero findings is not a stable target, because each fresh reviewer extends the checks (this one opened test bodies and re-expanded citations that earlier passes did not).
Options: (a) accept the core as `drafted` with the trail of eight reports and use it as a reference with the freshness/spot-check protocol (`knowledge-retrieval.md`); (b) define `validated` as "latest independent pass found no wrong or stale statement about system behavior", recorded as a change to the skill rules (this lowers the bar and should be an owner decision, not a quiet edit); (c) another pass on the round-8 edits (cost about 300k tokens, expected to find 1-3 more items). No change to the criterion was made in this run.

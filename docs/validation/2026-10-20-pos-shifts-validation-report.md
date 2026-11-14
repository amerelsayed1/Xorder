# Validation report: `pos-shifts`

Date: 2026-10-20 · Command: `validate pos-shifts` (run as part of the knowledge-integration dry run) · Repos: cloud `main 06bc8e3`, POS `main d592db8` (HEADs unchanged since the docs were written)
Validator: a fresh `code-reviewer` agent given only the docs and the source (no author notes), following `.claude/skills/project-documentation/references/validation-rules.md`. The author spot-checked every finding that was acted on by reading the cited source lines.
Result: **6 wrong, 10 missing/under-documented groups, 6 unverifiable items now resolvable, 5 style items.** Feature status before: `drafted`. After fixes: remains `drafted` (see "Status decision").

## Scope and what was not checked
Checked: FEATURE, API, DATABASE, TECHNICAL, WORKFLOWS in full; TEST_PLAN and TEST_REPORT briefly; about 75 citations opened by the validator plus mechanical range checks by the author (`136` line-level citations resolve after fixes, `0` problems).
Not checked: PostgreSQL behavior and lock behavior (SQLite-only evidence, reading only); `CHANGELOG` beyond a glance; template heading conformance; inventory completeness check 11; `day_close_dialog`, `management_shifts_pane`, `shift_history_providers`; behavior of locally created POS staff ids; no tests were run.

## Findings and disposition
| # | Severity | Finding (summary) | Source evidence | Disposition |
| --- | --- | --- | --- | --- |
| W1 | wrong | `shift.open` and `cash.movement` were said to be enforced in the shift repository; `shift.open` is a UI check only, `cash.movement` / `cash.open_without_sale` are enforced in the cash movements repository, which was missing from the docs | `P:lib/features/shift/presentation/shift_dialogs.dart:86`; `P:lib/data/postgres/postgres_cash_movements_repository.dart:150-158`; only call in the shift repo is `:354` | fixed in FEATURE (Actors), TECHNICAL, WORKFLOWS |
| W2 | wrong | "No `feature:` gate on this group"; `pos.device` gates the `pos` feature (403 `POS_FEATURE_DISABLED`), plus 401/403 device errors | `C:app/Http/Middleware/PosDeviceAuth.php:45,64,68,71-72` | fixed in FEATURE, API |
| W3 | wrong | FormRequest failures were documented as Laravel's standard shape; they are mapped to the POS envelope | `C:bootstrap/app.php:71-86` | fixed in FEATURE, API |
| W4 | wrong | "The drain quarantines rejected records" is over-general; six codes quarantine, all others defer | `P:lib/data/cloud/outbox_drain.dart:119-130` | fixed in FEATURE, API, TECHNICAL, WORKFLOWS |
| W5 | wrong | TEST_PLAN declared gaps for AC-4 and AC-8 that are covered (partly) by existing tests; other tests were missing from the lists | `C:tests/Feature/Pos/PosShiftsTest.php:155-168`, `PosRefundsTest.php:404`, `DashboardStatsTest.php:138`, `P:test/data/outbox_drain_test.dart:245-279,309-380` | fixed in FEATURE and TEST_PLAN |
| W6 | wrong | Header said no evidence file was uncommitted; two cited coordination docs were modified (other hunks) | `git status --short` in both repos | fixed (header reworded) |
| M1 | missing | `open` does not require `branch_id` to be the terminal's branch; close/report would then fail | `C:app/Services/PosShiftService.php:49-53,303` | documented under Security and Known limitations |
| M2 | missing | Contract vs built divergences (capabilities on GETs, 404 vs 422, close response, POS-BE-021 APPROVED not built, stale "not started" prose) | `apps/xorder-cloud/docs/coordination/BACKEND_TO_POS.md:215,744-810` | documented in API and FEATURE |
| M3 | unverifiable | malformed `{shift}` reference vs a uuid column on PostgreSQL | `PosShiftService.php:305-307` | marked UNVERIFIED |
| M4 | missing | unknown/inactive `acting_user_id` → 422; no test sends `acting_user_id` | `PosShiftService.php:328-332` | documented |
| M5 | missing | cloud attributes payments to a shift only when the order named an open shift of the same terminal; cloud/POS cash-sales differences | `C:app/Services/PosOrderService.php:503-513`; `P:...postgres_shift_repository.dart:440-464`; `migrations.dart:2203` | new BR-12 and AC-10; BR-2 expanded |
| M6 | missing | cash movement field mapping; second producer (supplier pay-outs); `drawer_open` mechanism | `outbox_drain.dart:774-810`; `postgres_cash_movements_repository.dart:165-200` | documented |
| M7 | missing | other consumers of `pos_cash_movements` (drawer-payouts endpoint, supplier payments, business-day close) | `C:routes/api.php:596`; `SupplierPayment.php:35,63`; `postgres_business_day_repository.dart:131` | documented |
| M8 | missing | dashboard tile data source and `analytics.view` gate | `C:StatsController.php:132-157`; `routes/api.php:341-342` | documented |
| M9 | missing | `openedBy` true when the opener is unknown; approver must be a different person holding `shift.close` | `P:lib/domain/models/shift.dart:150`; `authorization.dart:286-300` | documented |
| M10 | missing | idempotency hash fields; replay-before-capability ordering; DATABASE completeness (timestamps, branch_id, POS indexes/columns) | `PosShiftService.php:37,97,99-107,158`; migrations | documented |
| U1-U6 | unverifiable→resolved | `Idempotency-Key` not read by cloud; no consumer of `current`/`report`; role/permission key mapping at bootstrap; `Auditable` writes created/updated events; `order_payments.pos_shift_id` migration; `pos_sync_outbox` definition | greps and files cited in the docs | UNVERIFIED markers replaced |
| S1-S5 | style | off-by-two citations, imprecise double-close cite, "stored as sent" vs normalised time zone, API wording, POS-BE-021 status | | fixed |

Additionally the author's own mechanical check found 4 wrong citation prefixes (`C:docs/coordination/...` pointed outside the API folder); fixed.
Findings from the implementation-lookup agent not raised by the validator and now documented: POS cash policy (`cash.blind_close`, `cash.variance.view`), and the handover approval being recorded only in the POS local audit.

## Spot-check of the validator's claims
Verified by the author against source: W1, W2, W3, W4, W5 (including the test bodies), M1, M2 (contract text), M5 (order attribution), M6 (mapping and `drawer_open`), M8, M9, `Auditable`, `order_payments` migration, `Idempotency-Key` absence, outbox definition lines. None rejected. Not independently verified (stated as inference or UNVERIFIED in the docs): concurrent-open replay, the M1 lockout consequence, the terminal-deletion remark, PostgreSQL behavior of malformed references.

## Status decision
Rule: only a validation that finds no open `wrong`/`stale` item may set `validated`. This validation found six; they were fixed and re-checked by the author, but the corrected text has not been reviewed independently. The feature therefore stays **`drafted`** in `docs/FEATURE_INVENTORY.md` and `docs/DOCUMENTATION_PROGRESS.md` with `last validated: 2026-10-20 (6 wrong, fixed; re-validation pending)`. Next step: `/project-documentation validate pos-shifts` by a fresh reviewer.

## What this shows about the process
The first draft passed the mechanical citation check and still contained six wrong statements. Independent validation is what catches them, so drafts must not be treated as authoritative; `references/validation-rules.md` now lists these failure modes.

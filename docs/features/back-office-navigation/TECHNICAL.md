# Back Office navigation (XORD-022) — implementation plan

**Status (2026-10-25): stages 1–3 APPROVED by the owner and IMPLEMENTED (labels, moves, Finance payments merged into Reports, account menu); stages 4 and 5 not started and still need approval.** As built: `BackOfficeTab.account` (11th tab, drawn as the person's name), `PaymentLedgerSection`, Floor in Management. Everything below is the plan as approved; the as-built list and tests are in `docs/qa/XORDER_QA_FINDINGS.md` (XORD-022). Facts about today's navigation are in `NAVIGATION_INVENTORY.md` (same folder); this file is the plan only.
**Repo affected:** `xorder-pos` only. **No cloud change, no migration, no API/contract change, no payment or order-state change.** `xorder-cloud` is not touched, so nothing here can reach production.
**Source revision:** `xorder-pos` HEAD `2e7e612` with **79 uncommitted files**, including every file this plan touches (see Risk 1).

## Decisions recorded (owner, 2026-10-25, in chat)
1. **The epic replaces the 14–15 Sep 2026 map**; the navigation tests that pin it are edited deliberately, stage by stage.
2. **Finance › Payment methods (`financePayments`) is merged into the report** (Reports › Payment methods stays as the analysis; Settings › Payment methods stays as the only management page). Note for stage 2: what `financePayments` shows beyond the report ("every payment behind them") must be checked and kept in the report, so no information is lost.
3. **Account menu** = signed-in name, Switch user, Lock, Log out, About. Switch user and About leave Settings; the language and theme quick toggles stay in Settings.
4. **Work in place** in the current working tree (the diff will be mixed with the uncommitted work of other findings; I will not commit).

**Still undecided** (inventory section 7): Sales as one page or three items (default: keep one page); whether "Orders & invoices" leaves the till's Settings menu (default: keep it, renamed, until you say); Staff vs Employees wording; which pane gates to wire (stage 5, approval pane by pane); a package change for the dropdown (stage 4, approval).

## Acceptance criteria (proposed)
AC-1 No management page has two primary menu entries; every repeated label is on a documented list (022-A). AC-2 Each of the 46 panes has one primary menu location, in both languages (022-B). AC-3 Labels are consistent EN/AR and come from `AppStrings`, none hard-coded (022-C). AC-4 Settings holds configuration only; account actions are in one account menu showing the signed-in person (022-D). AC-5 One dropdown style with distinct hover, focus, active and disabled states, keyboard open, Escape to close, correct in RTL, inside the window (022-E). AC-6 Every pane's visibility follows an enforced capability, empty parents hidden, deep links refused, tested for owner, manager, cashier-grade admin and a custom role (022-F). AC-7 No existing page lost; `ManagementPane` names, `/management` and `/orders` unchanged.

## Business rules to preserve
Back Office reachable only through Admin Mode (`admin.enter`); cloud tills hide authoring panes and show pointers (`_authoringPanes`, `_pointsToPlatform`); the bar and `managementPanesFor` agree for everyone; Log out ends Admin Mode only, Switch user hands the till over; language and theme stay reachable without Admin Mode; the bar stays hidden before sign-in and on start/lock/welcome screens; cash-up and reprint are never gated by this work.

## Venue models (domain lens, `FOOD_SERVICE_DOMAIN.md` sections 2 and 6)
Helps all four: it only moves and names existing pages. Risks: **Floor / Dining areas and Shifts** mean nothing to a cloud kitchen and little to a food truck, and there is no venue-type field, so "hide because not applicable" is not solvable here and is out of scope (reported, not worked around). Arabic wording must be understandable to staff without training (question 6). No dependency on tips, KDS, aggregators or multi-brand.

## Stages (each ends with its tests green; nothing is ticked until a named test passes)
Order is by dependence. Stages 1–2 change names and placement only; stage 3 changes who gets which line; stage 5 changes who can see what and is the only one that can narrow access.

| # | Item | Change | Files (all `apps/xorder-pos`) | Proving tests | Rollback |
|---|---|---|---|---|---|
| 0 | baseline | done: nav tests `+61`; full `+3100 ~79`, analyze clean | — | — | — |
| 1 | 022-C, 022-A | Rename colliding labels: till line "Orders & invoices" vs "Orders & invoices settings"; Staff/Employees (EN) and الموظفون/الموظفين (AR) to one word; tab renames the owner approves (Home→Dashboard, System→Management, Settings items). New table-driven test: only listed labels repeat. | `lib/core/l10n/app_strings.dart` (EN + AR), `lib/app/app.dart` | edit `back_office_shell_test`, `settings_bar_test` label lists; new label-uniqueness test | revert the strings |
| 2 | 022-B, 022-A | Move `floor` out of Menu; resolve the Payment-methods triplicate per decision; Sales/Refunds per decision. Update `tabOf`, `_placeInTab`, `settingsSectionOf`, `_paneRequires`. New test: every pane has exactly one primary location and both labels. | `management_screen.dart`, `app_strings.dart` | edited map tests (l. 772, 805, 893, 918); new coverage test; the 1100 px fit test in EN and AR | revert `tabOf`/`_placeInTab` |
| 3 | 022-D | New account menu (last in the bar) showing the signed-in name: Switch user, Lock (if signed in at the till), Log out (Admin Mode), About. Remove Switch user and About from Settings. Quick language/theme toggles per decision. | `lib/app/app.dart`, `app_strings.dart` | new widget tests: contents per person, Switch user still goes to `/lock`, Log out still ends Admin Mode and returns to `returnTo`; edited `settings_bar_test` (l. 357, 661, 748, 775) | remove the menu, restore the lines |
| 4 | 022-E | **Spike first.** `menu_bar ^0.5.3` wraps Flutter's `MenuAnchor`; check what it offers (active-item style, width, RTL, Escape) before choosing: configure it, or move to Flutter's `MenuBar` directly (the code comments name that as the costly alternative: it re-homes every Settings line). Needs the running macOS app and before/after screenshots in EN and AR. | `lib/app/app.dart` (+ possibly `pubspec.yaml`, **needs your approval**: no new tooling without it) | widget tests: keyboard open, Escape, active highlight, RTL placement, fits at supported widths; screenshots | revert to current bar |
| 5 | 022-F | Wire pane gates from the decision list (candidates: `catalog.manage` → Menu/Categories/Extras/Combos/Floor; `staff.manage` → Staff/Roles; `settings.manage` → General/Tax/Charges/Payment methods; existing `order_types.manage`). Trace each pane's write path first; gate a pane only where its repository enforces the same capability (the file's own rule). | `management_screen.dart` (`_paneRequires`) | new tests: owner, manager, cashier-grade admin, custom role with one capability; deep link to a hidden pane refused; empty parent hidden; offline and cloud | revert `_paneRequires` |
| 6 | docs | `/project-documentation update` (add the inventory row, FEATURE, TEST_PLAN, TEST_REPORT, CHANGELOG), update XORD-022 criteria and section 8, `bash scripts/harness/verify.sh` | `docs/` only | — | — |

**Verification commands:** `cd apps/xorder-pos && flutter analyze && flutter test test/features/back_office_shell_test.dart test/features/settings_bar_test.dart`, then the full `flutter test`. PostgreSQL suites self-skip and are reported as not run. There is no screenshot or golden test today; the visual part needs the running app (`flutter run -d macos`).

## Approval gates (what needs your yes)
1. The decisions in `NAVIGATION_INVENTORY.md` section 7 (nine; the four that block stages 1–3 are asked below).
2. **Stage 5 narrows access:** an administrator who sees Menu, Staff or Settings panes today may lose them. Approve pane by pane.
3. **Stage 4** may need a package change.
4. No commit, push, merge or deploy is part of this plan; each needs its own approval.

## Risks
1. **Uncommitted work in the same files.** `management_screen.dart` (+115/−77), `app.dart` (+18, including the uncommitted Log out button), `app_strings.dart` (+399), and both navigation test files already carry uncommitted edits from earlier work, while other sessions edit the same tree (the XORD-014 work did during testing). My changes would be layered on top and could not be told apart in a diff. Needs your call: commit the current state first (I will not do it unasked), or work in a worktree from a clean base.
2. The two navigation test files encode the owner's current map; they will change deliberately in stages 1–3 and 5, which is the intended reviewable diff.
3. Window width: the bar is tested to fit in EN and AR; a longer label or one more menu can break that.
4. Cashiers outside Admin Mode reach order history only through the till's "Orders & invoices" line; removing it removes that path.
5. Dropdown behaviour, RTL placement and keyboard support are UNVERIFIED until stage 4's spike.

## Open questions
See `NAVIGATION_INVENTORY.md` section 7 (items 1–9).

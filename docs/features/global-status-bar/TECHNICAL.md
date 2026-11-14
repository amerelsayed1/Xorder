# Technical plan — global-status-bar
Status: **built 2026-10-26 (approved by the owner: "go")** · 2026-10-26 · Spec: `FEATURE.md` · Repo: `apps/xorder-pos` only · Source: `a6f5fe5` + 78 uncommitted files (not mine)

## Re-verified against the working tree
- `_StatusBar` `management_screen.dart:1851-1936`, mounted `:1506` as the last child of the screen's `Column`. `BackOfficeConnectionPill` `:1944`, used only there and in `back_office_shell_test.dart:731,735`.
- `app.dart:75` root `builder` → `TillIdleLock` → `_menuBar` → `CallbackShortcuts` → `Focus` → `_settingsBar(child)`. `_settingsBar` builds `MenuBarWidget(enabled, child: child)` inside `_AfterEachRoute` (rebuilds on every route change). `menu_bar-0.5.3/lib/src/bar.dart:77-94` lays it out as `Column[menu bar, Expanded(child)]`, so a `Column[Expanded(navigator), statusBar]` passed as `child` puts the bar under every screen without touching any screen's layout.
- Path hiding already exists: `_beforeTheTill(path)` (`app.dart`, start/lock/welcome) for the settings bar. Setup path is `PosRoutes.setup`. **Discrepancy with the spec found and fixed:** a manual Lock keeps the cashier signed in (only idle lock and the lock screen's Back sign out: `idle_lock.dart:127`, `lock_screen.dart:219`), so the person must also be hidden by route on Start/Lock. `FEATURE.md` BR-4/AC-3/Q2 updated.
- `PosTopBar` (`pos_top_bar.dart`) is only used by the sale screen. Its pill is `:62-92`; `branch · terminalCode` is in `_identity`.

## Design
1. **`TillStatusBar`**, new file `lib/app/till_status_bar.dart` (needs providers, so `lib/app`, not `lib/core`). `_StatusBar` and `BackOfficeConnectionPill` move there unchanged in look and logic, with two changes: the person comes from `actingStaffProvider` and is skipped when `showPerson` is false or the person is null; the person `Text` becomes `Flexible` + ellipsis (AC-8). `management_screen.dart` re-exports nothing; its one test reference is updated.
2. **Keys renamed** `back-office-status-*` → `till-status-*` (bar, branch, terminal, version, user), because the bar is no longer the back office's. Callers are two test files.
3. **Mount** in `app.dart`: `MenuBarWidget(child: Column(children: [Expanded(child: child), if (showBar) TillStatusBar(showPerson: !_beforeTheTill-ish)]))`. `showBar = path != welcome && path != setup`; `showPerson = path != start && path != lock`. The `Column` is always built and the bar is its last child, so the Navigator keeps its position (no reparenting, same reason as the settings bar's `enabled`).
4. **Management**: delete the `_StatusBar(admin: admin)` line, the class and its comment; keep `admin` where used elsewhere; drop imports that become unused.
5. **Sale top bar**: delete the pill block and the `branch · terminalCode` line; `_identity` keeps the tenant tile and name. Remove `ui`, `sync` and any import left unused. `session.branchName/terminalCode` stay on `PosSession` (other users).

## Stages, tests, rollback
| # | Change | Proof | Rollback |
|---|---|---|---|
| 0 | Baseline: `flutter analyze && flutter test` on the current dirty tree, recorded | output saved | — |
| 1 | `till_status_bar.dart` + new `test/features/till_status_bar_test.dart` (AC-1,2,3,4,7,8) | `flutter test test/features/till_status_bar_test.dart` | delete file |
| 2 | Mount in `app.dart` (AC-1,2,3 through the real router) | same test + `settings_bar_test.dart` still green | revert the `child:` line |
| 3 | Unmount from Management; update `back_office_shell_test.dart`, `admin_entry_test.dart` (AC-6) | those two files | restore class |
| 4 | Strip the sale top bar (AC-5); find and update any sale test that finds the pill or `branch · terminal` | sale tests; AC-9 at 1024×700 | restore block |
| 5 | Full `flutter analyze` + `flutter test`, compare with baseline; docs | outputs | — |

Closest test for what a test cannot prove (AC-9 look, AC-10 dialogs): widget builds at 1024×700 in both languages without overflow; a person checks the running till.

## Impact
No API, contract, schema, tenant, money or order change. Domain lens: helps food trucks and cloud kitchens (connection always visible); café counters lose 44 px of 700; restaurants unaffected. Docs after build: `FEATURE_INVENTORY.md` row, `/project-documentation update global-status-bar`, CHANGELOG, TEST_PLAN/TEST_REPORT.

## Approvals and open questions
- No migration, contract, payment, order-state or permission-narrowing approval needed. No commit, push or deploy is planned.
- **Needs your go** on this plan, and on building into a working tree that already holds 78 uncommitted files (`app.dart`, the sale tests and `management_screen.dart` among them); I will not revert or commit any of it.
- Open (defaults in `FEATURE.md` §13): Q1 keep the top bar's operator name and the account-menu name; Q3 till name, not code; Q4 pill stays tappable behind dialogs.

## As built — differences from the plan
- The bar needed a `Material` of its own (it sits above every screen's Scaffold and the connection pill is an `InkWell`); without it every full-app test threw "No Material widget found".
- `admin_entry_test.dart` needed a new "inside the back office" marker (`back-office-title`), because the old marker was the bar itself.
- `BackOfficeConnectionPill` moved with the bar to `lib/app/till_status_bar.dart` under the same name.
- Floor was not covered by a route test (see `TEST_REPORT.md`).

# Technical plan — pos-home-screen
Status: **built 2026-10-26 (owner: "go")** · 2026-10-26 · Spec: `FEATURE.md` · Repo: `apps/xorder-pos` only · Source: `a6f5fe5` + 148 uncommitted files (not this feature's; `router.dart` and `start_screen.dart` are among them)

## Re-verified against the working tree
- `branchOrderTypesProvider` (`providers.dart:1414`) is the list: active types in the restaurant's order ∩ the branch's supported types, never empty. `orderTypeRulesProvider` (`:1260`) gives `requiresTable` and each type's configured `displayName(locale)`.
- `StartScreen.onStart` is wired to `context.go(PosRoutes.floor)` (`router.dart:181`); the router sends `/floor` to the sale when `!hasSeating` (`:97`).
- `needsSignIn` (`router.dart:48`) is the one rule for "a selling screen with nobody signed in"; the router redirect **and** the idle lock (`idle_lock.dart:121-131`) both call it, so adding Home there covers both.
- `TicketController.setOrderType` (`providers.dart:1660`) is the existing switch (the top bar uses it); the new ticket already defaults to dine-in when offered, else the first offered type (`:1591`).
- Floor: `onClose` goes to Start (`router.dart:203`); `onSellWithoutTable` picks the first unseated type (`:218`).
- Lock → sale and Close shift → Start are not changed.
- No discrepancy with `FEATURE.md` found. Not traced: how a cloud till receives its order types (**UNVERIFIED**; Home reads the same providers as the sale screen).

## Design
1. **Route** `PosRoutes.home = '/home'` and `lib/features/home/home_screen.dart`: `HomeScreen({required void Function(OrderType) onPick})`. Shell ground like Start, one centred column (max 520), tenant name, one large `PosButton` per type from `branchOrderTypesProvider`, labelled `rules.forType(t)?.displayName(languageCode) ?? t.label(strings)`, a `KeyChip` with the number 1–4 on each; keys 1–4 pick, the first button autofocuses so Enter picks it. No other controls (D-3).
2. **Routing decisions in `router.dart`** (one place, three small helpers over `ref`):
   - `afterShift`: if the offered list has **one** type, open it directly; otherwise `go(home)`. `StartScreen.onStart` calls this instead of `go(floor)`.
   - `openType(type)`: if `rules.requiresTable(type)` → `go(floor)`; else `ticketProvider.notifier.setOrderType(type)` then `go(sale)`.
   - Floor's `onClose` goes Home when the branch has more than one type, Start otherwise (so Back from the Floor does not skip the screen it came from).
3. **Guard**: `needsSignIn` gains `PosRoutes.home` beside sale and floor (BR-6). The idle lock and redirect follow because they call it.
4. **Safety net inside Home**: if the list ever has one entry (the configuration arrived after Start decided), Home forwards once to `openType` instead of showing a single button. While `orderTypeConfigProvider` is loading it shows a progress indicator (Q-3 default).
5. **Nothing else moves**: Start's licence block, PIN and float; Lock → sale; Close shift → Start; the Floor's "sell without table"; the top bar's switch.
6. **Strings**: a heading only if one is needed; button names come from the configuration, so no new string for them.

## Stages, tests, rollback
| # | Change | Proof | Rollback |
|---|---|---|---|
| 0 | Baseline: `flutter analyze` and the route-touching suites (`sale_flow`, `sign_in`, `idle_lock`, `order_type_rules`, `status_bar`) | recorded output | — |
| 1 | `PosRoutes.home`, `needsSignIn` + its test list in `sign_in_test` | `needsSignIn(at: home, …)` true only when a shift is open and nobody is in; idle lock sends Home to Lock (`idle_lock_test` route list gains Home) | revert two lines |
| 2 | `HomeScreen` + `test/features/home_screen_test.dart` (AC-1, 2, 5, 7, 8) | one button per type, order, names in en/ar, live change, a tap calls `onPick`, 1024×700 Arabic no overflow | delete the folder |
| 3 | Router wiring: `afterShift`, `openType`, Floor `onClose`; tests through the real app (AC-3, 4, 5, 6, 9): two types → Home; one type seated → Floor; one unseated → sale with that type; seated tap → Floor; non-seated tap → sale with that type and no table; nobody signed in → Lock | `home_flow_test.dart` | revert the router edits |
| 4 | Full `flutter analyze` and `flutter test`, compare with the last full run (`+3329 ~81`); docs: TEST_PLAN, TEST_REPORT, CHANGELOG, inventory row | outputs | — |

## Impact and risks
- POS only: no API, contract, schema, migration, permission or deploy-order change; no money, tax or order-state rule changes (BR-8).
- Existing tests that assert routes may need Home added to a list; I will list each.
- Risk 1: no way back to Home from the sale screen (owner's decision D-3). Risk 2: the work sits among 148 uncommitted files; I will not revert or commit any.
- Domain lens: restaurant gains the most; café, food truck and cloud kitchen skip Home (BR-4) and see today's flow. Delivery is a plain type: no address or customer prompt (existing gap).
- Not provable by tests: the look and feel with real names and four types on a counter screen (AC-10).

## Approvals needed
Your go on this plan. No migration, contract, payment, order-state or permission change; no commit or push.
Open suggestions (defaults in `FEATURE.md` §13): Q-1 keys 1–4, Q-2 no way back, Q-3 wait for the first answer.

## As built — differences from the plan
- `afterShift` is asynchronous: it waits for `orderTypeConfigProvider` and `branchesProvider` before deciding, and `StartScreen` now also watches both. The plan's bare read saw the seeded four on a till that had not loaded them yet; a test found it.
- The helpers `openType`, `hasChoice` and `afterShift` are closures inside `routerProvider`, not top-level functions.
- No new string was needed: the buttons use the configured names and the existing `pointOfSale` line.

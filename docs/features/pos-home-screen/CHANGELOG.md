# Changelog — pos-home-screen

## 2026-10-26 — built (xorder-pos, uncommitted)
- New `lib/features/home/home_screen.dart`: `HomeScreen(onPick)`, one `PosButton` per type in `branchOrderTypesProvider`, labelled with `OrderTypeConfig.displayName` (fallback `OrderType.label`), a number chip each; keys 1–4 and the numpad choose; a wait while the configuration loads; forwards once by itself if the list holds one type.
- `lib/app/router.dart`: `PosRoutes.home = '/home'` and its route; `needsSignIn` includes Home (so the redirect and the idle lock treat it as a selling screen); local helpers `openType` (seated → floor, otherwise `setOrderType` then sale), `hasChoice`, and `afterShift` (waits for the order-type configuration and the branches, then Home when there is a choice, else straight on); Start's `onStart` calls `afterShift` instead of going to the floor; the floor's Back goes Home when there is a choice, else Start.
- `lib/features/start/start_screen.dart`: also watches `orderTypeConfigProvider` and `branchesProvider`, as it watches the catalogue, so they are loaded while the shift opens.
- Tests: new `home_screen_test.dart` (7) and `home_flow_test.dart` (8); `sign_in_test.dart` and `idle_lock_test.dart` extended for Home.
- Behavior to know about: a branch with more than one order type now sees the home screen after Start (it went to the floor, or the sale, before); a branch with one sees no change. There is no way back to Home from the sale screen except Start (owner's decision).

## 2026-10-26 — fix: Home skipped when a shift is resumed with nobody signed in
- The owner saw the flow unchanged. Cause: Resume with nobody signed in (the usual way after a restart) went Home → sign-in guard → lock screen, and unlocking always went to the sale, so Home never showed. The old Floor step had the same gap.
- `lib/app/router.dart`: `lockLocationFrom(at)` puts the screen in the lock location (`/lock?next=…`); the redirect and the idle lock (`idle_lock.dart`) use it; `unlockTarget(next)` returns `home`, `floor` or `sale` and falls back to the sale for anything else; the lock route unlocks to it. Pressing Lock at the till carries nothing and still returns to the sale.
- Tests: `home_flow_test.dart` +4 (resume then unlock → Home; Lock at the till → sale; the unlock target rule; the location round trip).
- Behavior change to know about: after an idle lock on the floor, unlocking now returns to the floor (it went to the sale before).

## 2026-10-26 — Escape is "back"
- Owner: "back in general it will do pop if possible". `HomeScreen` gains `onBack` (Escape → Start); `FloorScreen` binds Escape to its `onClose`; `LicenceScreen` binds Escape to its `onClose`; `SaleScreen` gains `onBack` and, once a typed search is cleared and no other text box has focus, calls it. `OrderHistoryScreen` already did this.
- `lib/app/router.dart`: `leaveSaleTo(context, location)` is the old `onTables` body (park a seated ticket with items, then go) and now serves both the Tables button and Escape; the sale's `onBack` goes to the floor for a seated type, otherwise Home, otherwise nothing.
- Tests: `home_flow_test.dart` — eight Escape cases (floor → Home, Home → Start, sale → Home, search cleared first, seated bill parked and sent to the floor, one-way seated floor → Start, one-way sale stays, licence → Start); `home_screen_test.dart` — Escape reports a step back.
- Behavior to know about: leaving the sale by Escape never drops out to Start; that stays Close shift's deliberate act.

## 2026-10-27 — amended by pos-signin-first-home (xorder-pos, uncommitted)
- Home now carries Start shift, Sign out and Close the day (permission-gated) and has a no-shift state; it is reached after the Start-screen sign-in, not after a shift opens. A one-type branch skips Home only when a shift is open. Home with nobody signed in goes to Start; the idle lock on Home signs out and goes to Start. Details in `FEATURE.md` section 15 and `docs/features/pos-signin-first-home/`.
- Tests: `home_screen_test` (+7, harness gains a signed-in person and a shift state), `home_flow_test` (resume helper now signs in at Start; two route tests rewritten), `idle_lock_test` and `sign_in_test` (Home expectations changed), new `signin_first_flow_test`.

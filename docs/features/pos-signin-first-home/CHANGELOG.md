# Changelog — pos-signin-first-home

## 2026-10-27 — built (xorder-pos, uncommitted)
- **Start** is a name-and-PIN sign-in (`SignInDialog`); it opens no shift and the licence never blocks it. "Close the day" and the stale-shift "Resume" wording left this screen. (`lib/features/start/start_screen.dart`)
- **Home** is where a shift is started (`shift.open`, float only, `OpenShiftDialog(by:)`), the day is closed (`day.close`, open day), and the person signs out. Order types are dead until a shift is open, with "Start a shift to sell." (`lib/features/home/home_screen.dart`)
- **Router**: `afterSignIn` (Home, or straight on for a one-type branch with a shift open); Home with nobody signed in goes to Start; `needsSignIn` no longer includes Home; the lock route unlocks to Home when no shift is open. (`lib/app/router.dart`)
- **Idle lock** on Home signs out and returns to Start. (`lib/features/lock/idle_lock.dart`)
- **Day close** records the acting person as the closer (the silent no-op with nobody signed in at the till is fixed). (`lib/features/cash/presentation/day_close_dialog.dart`)
- Strings (EN, AR): `signInOnlyHelp`, `signedInAs`, `signOut`, `startShiftToSell`.
- Docs amended: `pos-home-screen` (section 15), `pos-business-day`, `pos-shifts`.
- Behavior to know about: sign-in and opening the drawer are two steps (one extra tap for a cashier); cashiers no longer see Close the day, so the "manager approves it with a PIN" route from Start is gone (a manager signs in instead).

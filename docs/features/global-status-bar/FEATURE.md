# Global status bar on every POS screen — global-status-bar

Status: built, uncommitted · 2026-10-26 · Source: the owner's request, "this should appear on all screens got it", with a screenshot of the Management bottom bar · Verified against: xorder-pos `a6f5fe5` **plus 78 uncommitted modified files** (the XORD-022 work in progress; line numbers below are of that working tree), xorder-cloud `06bc8e3` (not touched by this feature)

## 1. Summary
The thin bottom line that Management shows today (connection, branch, till name, version, who is in) becomes one bar at the bottom of the till window, on every screen of a set-up till except the welcome screen and the setup wizard. Who is in shows whoever is signed in, and is left out where nobody is. The sale screen's top bar stops drawing its own connection pill and branch · terminal, so none of it appears twice.

## 2. Why
Support asks over the phone for the branch, the till, the version and whether the till is connected. Today those facts exist only inside Management, so a cashier on the sale screen, the floor or the lock screen cannot read them out. A cashier cannot tell which counter they are standing at, or whether the branch server is reachable, from anywhere but the sale screen's pill.

## 3. Goal and success
- Every screen of a configured till shows the same bar in the same place, in Arabic and English, built from the same providers the Management bar uses today.
- The sale screen shows each fact once.

## 4. Users, roles and permissions
Display only: every signed-in role sees it, and nobody needs a permission to see it. The bar shows whoever is signed in, or the person in Admin Mode inside Management. It does not sign anybody in or out, and nothing on it grants access.

## 5. Today
| What | Where | State |
|---|---|---|
| The bar | `_StatusBar`, `lib/features/admin/presentation/management_screen.dart:1851-1936`; mounted at `:1506` | **Management only.** Connection pill, branch name, till name, `v$posAppVersion`, then `name · role`. Keys `back-office-status-bar/-branch/-terminal/-version/-user`. Hides branch or till name when the profile has none. |
| Connection pill | `BackOfficeConnectionPill`, same file `:1944` | Cloud till: `SyncPill`; otherwise `BranchServerPill`. Same choice as the sale top bar. |
| Sale top bar | `lib/features/sale/widgets/pos_top_bar.dart` | Draws its own pill (`:62-92`, same cloud/offline choice), the identity block `tenantName` + `branchName · terminalCode` (`_identity`, near `:190`) and the signed-in operator's avatar and name. Only the sale screen has it. |
| Root of the app | `lib/app/app.dart:75` `builder:` → `TillIdleLock` → `_menuBar` → `CallbackShortcuts` → `_settingsBar(child)` | The one place above every route. Also the place the app-level chords live. |
| Account menu | `lib/app/app.dart` (XORD-022-D, uncommitted) | The settings bar already carries the signed-in name (`accountName`, Switch user / Lock / Log out). A third place that names the person. |
| Who is signed in | `signedInStaffProvider` (`providers.dart:1791`, null until a PIN is entered); `actingStaffProvider` (`:1953`) = admin session's staff, else signed-in staff | Exactly the "who" this feature needs. |
| Window | `lib/main.dart:18` minimum 1024×700; bar height `PosSize.minTouchTarget` = 44 (`tokens.dart:428`) | The sale and floor screens lose 44 px of height. |
| Route guard | `lib/app/router.dart` redirect | An unconfigured till can only be at `/welcome` or `/setup`; a configured one is sent away from both. "Except welcome and setup" is therefore the same as "except an unconfigured till". |
| Existing tests | `test/features/back_office_shell_test.dart:684,1099,1160-1203`; `test/features/admin_entry_test.dart:136` | Rely on the `back-office-status-*` keys inside Management. |
| Cloud back office | `CloudBackOfficeScreen` (router, claimed cloud tenant) | No bar of its own today (no `_StatusBar` reference found). **UNVERIFIED** that nothing else draws one. |

## 6. Scope
**In:** one bar mounted once at the root; the user part driven by who is signed in; removing the Management mount; removing the sale top bar's pill and `branch · terminal`; tests; docs.
**Out:** any change to what the bar's facts mean or where they come from; new facts (no clock, shift, printer or battery); API, schema, permissions; the welcome screen and the wizard; the native/settings menu bar; the idle-lock timing.

## 7. Behavior and business rules
- **BR-1** The bar shows, in this order: connection pill, branch name, till name, version, then on the far side the signed-in person. Same content, order and styling as Management's today (screenshot). Layout mirrors in Arabic.
- **BR-2** Connection: cloud till shows the sync state, any other till shows the branch server, exactly as `BackOfficeConnectionPill` decides today. Tapping it does what it does today (sync now, or re-probe).
- **BR-3** Branch name and till name are left out when the terminal profile has none (existing rule).
- **BR-4** The person is `actingStaffProvider`'s: the Admin Mode person inside Management, otherwise whoever is signed in. **Not drawn on Start and Lock, and not drawn when nobody is signed in**; the rest of the bar still is. *(Corrected 2026-10-26 during planning: a manual Lock keeps the previous cashier signed in, so "nobody is signed in" alone would print their name on the lock screen. Hiding by route as well follows the settings bar's own rule, `_beforeTheTill` in `app.dart`.)*
- **BR-5** Not shown on `/welcome` and `/setup` (the till has no branch, name or user yet).
- **BR-6** One instance, outside any screen: switching screens does not rebuild or flicker it. Management no longer draws its own.
- **BR-7** The sale top bar no longer shows the connection pill or `branch · terminal`. Its tenant name tile, order-type switch, drawer, shift, Lock and Close shift stay as they are.
- **BR-8** The version is the `posAppVersion` mono, left-to-right in both languages (existing rule).

## 8. Acceptance criteria
- **AC-1** Given a configured till, when on each of Start, Lock, Floor, Sale, Orders, Licence and Management, then one bar with the connection pill, branch, till name and version is visible at the bottom. *Widget test per route.*
- **AC-2** Given an unconfigured till on `/welcome` or `/setup`, then no bar. *Widget test.*
- **AC-3** Given Start or Lock (even with a cashier still signed in behind them), or nobody signed in anywhere, then the bar has no person text and the rest is present; on Sale, Floor, Orders and Licence with somebody signed in, the person appears. *Widget test.*
- **AC-4** Given a cashier is signed in on the Sale screen, then the bar names them; given Admin Mode in Management, then it names the administrator with their role (current behavior). *Widget test.*
- **AC-5** Given the Sale screen, then the connection pill and `branch · terminal` appear once on the whole screen (in the bar), not in the top bar. *Widget test counting finders.*
- **AC-6** Given Management, then exactly one `back-office-status-bar` exists. *Widget test (existing tests adapted).*
- **AC-7** Given a cloud till versus an offline till, then the pill is the sync pill versus the branch-server pill. *Widget test.*
- **AC-8** Given Arabic and English, then the bar lays out right-to-left and left-to-right and the version stays LTR; a long branch or till name ellipsizes with no overflow error at the 1024 px minimum width. *Widget test at 1024×700.*
- **AC-9** Given the Sale screen at the 1024×700 minimum window, then the layout builds with no overflow after losing the bar's height. *Widget test; a person confirms it looks right.*
- **AC-10** Given a dialog is open over a screen, then the bar stays visible and does not break the dialog or the idle lock. *Needs a person to look; a widget test covers that it builds.*

## 9. Edge cases and failure modes
- **Height:** −44 px on every screen, 6% of the 700 px minimum. The sale item grid and the floor plan are the screens to check. Cafés (speed, small counter screens) are the venue most exposed.
- **Long names:** the person text in today's bar is not `Flexible`, so a long name plus long branch and till names can overflow. Must be made safe now that the bar is on every screen.
- **Terminal text differs:** the top bar printed `terminalCode`; the status bar prints `terminalName`. After the change the code is no longer on the sale screen. Support asks for the till, so the name is probably enough, but this is a visible change.
- **Offline / retry:** unchanged, the pill reads the same providers. The bar lives above the router, so a probe failure must not throw into the root.
- **Dialogs and shortcuts:** the bar sits outside the Navigator, so dialog scrims will not cover it and its pill stays tappable. Root-level idle lock (`TillIdleLock`) treats a tap anywhere as activity; a tap on the pill therefore resets the idle timer, as any tap does.
- **Tenant / money / order integrity:** not touched.
- **Plan and licence limits:** none; shown regardless of plan.

## 10. Impact
- **Apps:** POS only (`apps/xorder-pos`). No cloud, API, contract (`docs/coordination/`), schema or migration change. Cloud deploy and rollout order: not applicable.
- **Files likely touched:** `lib/app/app.dart` (mount), `lib/features/admin/presentation/management_screen.dart` (unmount; move or expose the widget), `lib/features/sale/widgets/pos_top_bar.dart`, the three or four tests above, and new widget tests.
- **Localization:** no new strings; `strings.noRole` and role names are reused.
- **Docs:** `docs/FEATURE_INVENTORY.md` (add a row), `docs/features/back-office-navigation/`, `/project-documentation update global-status-bar`.
- **Working tree:** the POS repo already holds 78 uncommitted files, including `app.dart` and the sale tests. The change will be mixed with that unfinished work and must be reviewed as such.

## 11. Dependencies, known gaps, risks
- Depends on the root builder staying the single place above all routes.
- Risk: layout regressions on the sale and floor screens from the lost height. Risk: the bar shown twice if Management's mount is missed. Risk: existing tests keyed on `back-office-*` break if the keys are renamed.
- No known gap from `FOOD_SERVICE_DOMAIN.md` §3 or §7 is relied on. Venue models: helps food trucks and cloud kitchens most (a visible connection state on every screen); the café counter is the one that pays in screen height; restaurants lose nothing they use.

## 12. How it will be tested
Flutter widget tests only, run with `flutter test` for the touched files and then `flutter analyze` (the PostgreSQL-tagged suites self-skip and will be reported as not run). AC-1 to AC-9 each map to a widget test; AC-9 and AC-10 also need a person to look at the running till at 1024×700 in Arabic and English. No cloud tests apply.

## 13. Decisions and open questions
**Decided (2026-10-26, the owner):**
1. On every screen except the welcome screen and the setup wizard.
2. The person is the signed-in staff member (cashier or admin) and is hidden on Start and Lock where nobody is signed in.
3. The sale top bar's duplicate connection pill and `branch · terminal` are removed.

**Still open (defaults used if not answered; suggestions, not requests):**
- Q1. The sale top bar's operator avatar and name, and the account menu's name, now repeat the bar's person. Default: leave both, since you named only the pill and `branch · terminal`.
- Q2. ~~Show the person on Start when someone is already signed in?~~ Resolved in planning: no. Start and Lock never show the person (see BR-4).
- Q3. The sale top bar printed the till's *code*, the bar prints its *name*. Default: the name only.
- Q4. Should a tap on the pill stay active behind an open dialog? Default: yes, nothing special.

## 14. As built (2026-10-26)
Built as planned in `TECHNICAL.md`; see `CHANGELOG.md` and `TEST_REPORT.md`. Open questions Q1 (top bar's operator name and the account menu's name kept), Q3 (till name only) and Q4 (pill stays tappable behind dialogs) were taken at their defaults, not answered. Q2 was resolved in planning (no person on Start and Lock).

# Sign in first, then Home: shift and "Close the day" after login — pos-signin-first-home

Status: **proposed** · 2026-10-26 · Source: the owner, this session: "close day should appear in new home screen and appear only if the logged user have permission to do that" · "Close day should be from the back office" · "if we make it like foodics where this button should appear?? I think of shift button should be after login not in login ?? Because if admin try to close the day he will need to open new shift to do that ?" · Verified against: xorder-pos `5cf13cc` + uncommitted work (28 files, see §11; not all this feature's), xorder-cloud `775bf0f` (not touched; its tree has unrelated uncommitted tender/financial-account edits)

> The `/develop-feature` call arrived with no text. This description is built from the owner's four statements above. Where they pointed two ways (close day in the back office vs. close day after login on Home) both are recorded, and the choice is in §13 as open question Q1.

## 1. Summary
Today the till has no login of its own: the Start screen's "Start shift" button *is* the login, because it asks for name and PIN and then the opening float in one dialog. This feature splits the two. A person **signs in first** (name and PIN, no drawer), lands on the Home screen, and from there sees only what their permissions allow: **Start / Resume shift**, the order-type buttons, and **Close the day**. A manager can therefore close the day without opening a shift.

## 2. Why
- **An admin who only wants to close the day must not open a drawer.** A close-day is *blocked* by open shifts (`DayBlockerKind.openShift`, `lib/domain/models/business_day.dart:56`). If it lived behind "Start shift" the admin would open a shift with a float just to close it again, leaving a cash record behind.
- **The button is offered to everyone.** On Start, "Close the day" is shown whenever a day is open, with nobody signed in and no permission check until the button is pressed (`lib/features/start/start_screen.dart:305`). The permission is only asked inside the dialog (`day_close_dialog.dart:318`).
- **Venue models:** restaurant and café, where a manager closes at night while the floor staff have gone home (helps). Food truck and cloud kitchen, where the owner is the only user (neutral, one extra tap to sign in, see §9).
- Competitors checked this session (search summaries, **UNVERIFIED** beyond that): Foodics, Toast, Lightspeed K-Series and Square all run end-of-day from the POS behind a manager permission and block it while work is open. Foodics requires the till to be closed first, so closing the day never depends on an open till.

## 3. Goal and success
A manager signs in, taps "Close the day" and closes it, never creating or opening a shift. A cashier without `day.close` never sees the button. A cashier's morning is: sign in, Start shift (float), sell.

## 4. Users, roles and permissions
| Action | Who | Permission (existing, `lib/domain/models/permissions.dart`) |
|---|---|---|
| Sign in to the till | any active staff member with a PIN | none new |
| Start / Resume shift | holders of `shift.open` | `shiftOpen` (`:105`) |
| Close the day | holders of `day.close` | `dayClose` (`:132`) |
| Close over blockers | `day.force_close`, with a reason | `dayForceClose` (`:133`) |
| Back office (Admin Mode) | `admin.enter`, entered with **username and password**, a separate session | `adminEnter` (`:174`) |

No new permission. Hiding is courtesy, enforcement stays where it is: the dialog asks for the permission again before it closes anything (`day_close_dialog.dart:315-326`), and a supervisor can approve with their PIN. The seeded cashier role appears not to hold `day.close` (it is listed for the owner and manager-type sets near `permissions.dart:688-715`); **UNVERIFIED** against the seeded role table.

## 5. Today (verified in source, `apps/xorder-pos`)
| Fact | Where |
|---|---|
| Start's "Start shift" with no shift open opens `OpenShiftDialog`: name + PIN, then the opening float. With a shift open it resumes without a PIN. | `start_screen.dart:63-82`, `shift_dialogs.dart:80-160` |
| Verifying the person, and checking `shift.open` for them, are inside that dialog, as is signing the person in at the till. | `shift_dialogs.dart:92`, `:113`, and `signIn(staff)` after the shift is inserted |
| The business day is opened by the person opening a shift, *before* the shift row; and on lock-screen sign-in when a shift is open. | `shift_dialogs.dart:155`, `lock_screen.dart:183` |
| The licence blocks opening a shift only. Cash-up is never gated. | `start_screen.dart:73,160` |
| Sale, floor and Home with a shift open and nobody signed in go to the lock screen. With no shift open they do not. | `router.dart:51-58` (`needsSignIn`) |
| Home appears after a shift is open; Start is "the shift gate". Home is skipped for a one-order-type branch. | `docs/features/pos-home-screen/FEATURE.md` BR-1, BR-4; `home_screen.dart` |
| "Close the day" is a small button on Start, shown whenever a day is open, no permission check before it is pressed. | `start_screen.dart:305-316` |
| Day close lists blockers (open shift, parked ticket, unpaid order), totals the day, takes the automatic backup if configured. | `postgres_business_day_repository.dart:119-250`, `day_close_dialog.dart` |
| The dialog's permission check uses `actingStaffProvider` (the Admin Mode person, else the till's person), but it records *who closed* from `signedInStaffProvider` and silently returns if that is null. | `providers.dart:1971`; `day_close_dialog.dart:329` |
| Admin Mode is entered with username and **password**, is separate from the till, and does not change who is signed in at the till. | `admin_session.dart` header comment |
| Cloud: no route, payload or migration carries the business day or this flow. | `docs/features/pos-business-day/FEATURE.md` "Cloud flow" |
| Existing tests around this: `sign_in_test`, `start_gate_test`, `idle_lock_test`, `home_flow_test`, `home_screen_test`, `business_day_opening_ui_test`, `cash_dialogs_test`, `admin_entry_test`. | `test/features/` |
| Uncommitted, mine, this session: a permission-gated "Close the day" on `HomeScreen` (`home_screen.dart:109-113`, key `home-close-day`) and its test `test/features/home_close_day_test.dart` (4 tests, passing). Never committed. | working tree |

## 6. Scope
**In**
- A sign-in step that does not open a shift: name and PIN, same lockout rules (`signInLimiterProvider`), landing on Home.
- Home shows, per permission: Start / Resume shift, the order types, and Close the day.
- "Close the day" works with no shift open, for the signed-in holder of `day.close`.
- The dialog records the closer from the acting person (also needed for the back office, see Q1).
- Both languages, RTL, tests, docs.

**Out**
- Any change to cash-up, shift close, the float, variance or blind-close rules.
- Any cloud route, contract or migration (none found to be needed).
- Auto-closing the day at a set hour (Toast does; a separate feature).
- The business-day roll-over rule (`day.start_time`) and its missing editor.
- Removing the stale-day banner from Start (someone's uncommitted change, §11).

## 7. Behavior and business rules
- **BR-1** Start becomes a sign-in screen. A correct name and PIN signs the person in at the till and goes to Home; nothing is written to `pos_shifts`.
- **BR-2** On Home, **Start shift** (or **Resume shift** when one is open) is shown only to a person holding `shift.open`; the licence block applies to it exactly as it does today (`canOpenShift`), and the refusal text stays.
- **BR-3** Order-type buttons stay as in `pos-home-screen`, but selling needs an open shift (**Q2**: disabled or hidden until one is).
- **BR-4** **Close the day** is shown only while a business day is open **and** the signed-in person holds `day.close`. It opens the existing dialog; blockers, force-close with a reason, the backup hook and the result toast are unchanged.
- **BR-5** Closing the day requires no open shift of the closer. An open shift anywhere is still a blocker.
- **BR-6** The permission is checked again inside the dialog; a refusal or supervisor approval is audited as today (`day.closed` / `day.force_closed`).
- **BR-7** A person who is signed in but may do nothing else (no shift, no day close) sees Home with no actions, only their name and Sign out. **Q5.**
- **BR-8** Money, tax, order-state and idempotency rules are untouched.

## 8. Acceptance criteria
- **AC-1** Given nobody signed in, when a correct name and PIN is entered on Start, then the till is signed in and Home shows, and no shift row exists. *Widget + fake-repository test.*
- **AC-2** Given a signed-in person without `shift.open`, then Home has no Start-shift button. Given one with it, the button shows and opens the float step. *Widget test.*
- **AC-3** Given a signed-in person with `day.close` and an open day, then "Close the day" shows; without the permission, or with no open day, it does not. *Widget test (4 cases already written for the current Home, `home_close_day_test.dart`).*
- **AC-4** Given a manager with `day.close`, no shift open and no blockers, when they close the day, then `pos_business_days.closed_by` is that manager and no shift was created. *Test with the fake business-day repository; PostgreSQL behaviour is integration-tagged.*
- **AC-5** Given an open shift, then the dialog lists it as a blocker and "Close the day" needs `day.force_close` and a reason. *Existing `cash_dialogs_test` stays green.*
- **AC-6** Given the lock screen, sale or floor with a shift open and nobody signed in, then the till still goes to the lock screen; Home with nobody signed in goes to Start. *Router test (`sign_in_test` style).*
- **AC-7** Given the wrong PIN five times, then sign-in locks out exactly as the shift dialog's does today, and the same message is shown for an unknown name. *Existing `sign_in_lockout_test` pattern.*
- **AC-8** Given Arabic at 1024×700, then Start and Home lay out right-to-left with no overflow. *Widget test.*
- **AC-9** Given a licence that blocks opening shifts, then a manager can still sign in and close the day and cash-up. *Widget test.*
- **AC-10** Existing flows keep working: resume after a restart (lock → Home), Lock at the till, idle lock, the one-type branch skipping Home. *Existing tests pass, updated only where a route moved.*

## 9. Edge cases and failure modes
- **Offline / cloud:** sign-in already verifies against the cached staff hash; no new network dependence.
- **Concurrency:** two tills closing the day: the repository already returns the already-closed day (`postgres_business_day_repository.dart`, "Somebody else closed it first").
- **A day left open overnight:** unchanged: reused until closed.
- **Tenant boundary:** everything runs through the existing branch-scoped repositories; no cross-tenant read is added.
- **Retry:** closing is idempotent in effect (`closed_at IS NULL` guard).
- **Food truck / café, one person:** one extra sign-in tap before the shift. Mitigation (**Q3**): sign-in remembers the last name, as the lock screen does (`lastUsernameProvider`).
- **Idle lock and Home:** with a shift open the idle lock signs the person out; with none open it must not strand an unattended signed-in manager (**Q4**).
- **Arabic:** all new strings in both languages; digits via `foldDigits`.
- **Business day opening:** today it is opened by shift-opening or lock-screen sign-in with a shift open. With sign-in-first, a day may not exist when a manager signs in; "Close the day" is then simply absent, which is correct. See **Q6** about where the day should open.

## 10. Impact
| Area | Impact |
|---|---|
| Apps/repos | `xorder-pos` only. `xorder-cloud` untouched. |
| API / contract | none. No READY item involved. |
| Data / migrations | none expected. |
| Permissions | no new ones; **narrows** what a cashier sees (close-day hidden), does not narrow what they may do (it was already refused in the dialog). |
| Localization | new strings (Sign in as a Start action, Sign out); both languages. |
| Code | `start_screen.dart`, `shift_dialogs.dart` (split sign-in from float), `router.dart` (`afterShift`, `needsSignIn`), `home_screen.dart`, `lock_screen.dart`, `day_close_dialog.dart` (actor). |
| Docs | `pos-home-screen` BR-1 and BR-6 change; `pos-business-day` (where the day opens, notice); `pos-shifts`; `pos-lock-signin` (inventory row, UNVERIFIED). Run `/project-documentation update` for each. |
| Deploy order | POS only; no ordering with cloud. |
| Needs approval | changes to shift-opening and sign-in (cash/shift integrity), per workspace rule 4. |

## 11. Dependencies, known gaps, risks
- **Risk (high):** this reworks the front door of the till (sign-in, shift open, resume after a restart, idle lock). Every till path starts here. Needs a staged plan and the full widget suite, not just new tests.
- **Risk:** `pos-home-screen` was documented as "Start stays the shift gate" and is **built but uncommitted**; this feature changes it before it ships. Better done together than after release.
- **Risk:** the dialog silently does nothing if `signedInStaffProvider` is null (`day_close_dialog.dart:329`); must be fixed whichever door is chosen.
- **Unrelated uncommitted POS work, left untouched:** `start_screen.dart` (stale-day banner and its imports removed), `shift_dialogs.dart` (Esc-to-cancel wrapper), `test/features/business_day_opening_ui_test.dart`, `test/features/close_shift_dialog_test.dart`, plus the tender and financial-account edits in both repos. Anyone committing must not sweep them in by accident.
- **Known domain gaps leaned on:** none of tips, aggregators, KDS, recipes, loyalty, multi-brand.
- **UNVERIFIED:** seeded role contents; competitor behaviour beyond search summaries; what `Authorization.check` returns for `null` staff when the Start-screen button is pressed today (the code says null is a denial, not what `requestPermission` then shows).

## 12. How it will be tested
| AC | Test |
|---|---|
| AC-1, 2, 3, 8, 9 | widget tests with fake repositories (1440×900 and 1024×700) |
| AC-4 | widget/unit test with a fake business-day repository recording the closer |
| AC-5, 10 | existing suites re-run: `cash_dialogs_test`, `start_gate_test`, `home_flow_test`, `idle_lock_test`, `sign_in_test` |
| AC-6, 7 | router tests in the style of `sign_in_test` / `sign_in_lockout_test` |
| PostgreSQL behaviour of day close with no shift | integration-tagged, needs a local PostgreSQL (`scripts/check.sh`); not run in CI |
| Needs a person to look | layout and flow on a real till, Arabic; an admin closing the day with no shift ever opened |

## 13. Decisions and open questions
**Decided**
- **Plan approved 2026-10-26 (owner), with the defaults** for Q2 to Q6 (disabled order types with a reason, remember the last name, idle lock returns to Start, a person with nothing permitted sees name and Sign out, the business day still opens with the first shift) and for A1 to A5.
- **Q1, 2026-10-26 (owner):** Close the day lives on the **post-login Home**, with sign-in split from shift-opening. Not in the back office. The back-office copy and the "closed by" fix for Admin Mode are therefore not needed by this feature (the fix to use the acting person in `day_close_dialog.dart:329` stays, as a safe default).

**Open, with a recommendation each**
- **Q2 Before a shift is open, are the order-type buttons disabled or hidden?** *Recommend disabled with the reason "Start a shift to sell", so the screen explains itself.*
- **Q3 Remember the last user name at sign-in?** *Recommend yes, as the lock screen does.*
- **Q4 Should a signed-in person with no shift open be signed out by the idle lock?** *Recommend yes, same timeout; an unattended signed-in manager is a risk.*
- **Q5 Home for a person with no permitted actions:** show their name and Sign out only? *Recommend yes.*
- **Q6 Who opens the business day when nobody has started a shift?** Today the first shift does. *Recommend keep it with the first shift (no change), accepting "Close the day" is absent until then.*
- **Suggestion, not requested:** Toast-style auto-close at a configured hour, for restaurants that forget. Left out of scope.

Next: `/implement pos-signin-first-home` after Q1 to Q6 are answered. It will need approved: the sign-in/shift-opening split (cash and shift integrity), the `pos-home-screen` rule change, and a plan for the lock/resume paths. No migration, contract change or cloud push is expected.


## 14. As built (2026-10-27)
Built as planned in `TECHNICAL.md` (stages S1 to S7); see `CHANGELOG.md`, `TEST_PLAN.md`, `TEST_REPORT.md`.
- **Deviations from the plan.** (1) `OpenShiftDialog` with `by:` re-checks `shift.open` in `_open`, because the PIN step that used to check it is skipped. (2) After an independent review, **Lock and Switch user with no shift open unlock to Home, not the sale** (`router.dart`, the lock route), because somebody can now be signed in with no drawer and a sale would otherwise be taken with `shift_id` NULL. (3) Home does not forward a one-type branch while the float dialog is open. (4) A wrong PIN at Start nudges the platform sync, as the lock screen does. (5) The idle lock on Home returns to Start with or without a shift open (a signed-in person on an unattended Home is the risk), not only without one.
- **Known and left alone.** Sign out (and the idle lock) leaves an unseated cart in memory, so the next person to sign in on a one-type branch with a shift open inherits it. This is how Lock has always behaved; whether the next person should be asked to take a ticket over is the product question already recorded in `lock_screen.dart`. If the shift state cannot be read when signing in, Home offers Start shift although one is open; the repository then returns the existing shift and the typed float is discarded (it is still audited).
- **Not done.** The name+PIN+float form of `OpenShiftDialog` has no product caller and was kept (its tests); `resumeShift`/`resumeShiftHelp` strings may now be unused; `/project-documentation update` and `validate` were not run through the skill (the four affected feature docs were amended by hand); the integration driver was edited but not run; Arabic strings need a native reader.

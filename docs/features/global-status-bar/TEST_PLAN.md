# Test plan — global-status-bar
Planned 2026-10-26. Executed results live in `TEST_REPORT.md`. All tests are Flutter widget tests in `apps/xorder-pos/test/features/`; there is no cloud, API or database part.

| AC | Proof | Test |
|---|---|---|
| AC-1 every set-up screen has the bar | Start, Lock, Orders, Licence, Sale each show it, with the pill, branch, till and version | `till_status_bar_test.dart` "every screen of a set-up till has it" |
| AC-2 not on welcome / setup | unconfigured till on `/welcome` and `/setup` | "the welcome screen and the wizard do not" |
| AC-3 person hidden on Start/Lock, shown elsewhere | cashier still signed in on Start/Lock: no person; Orders/Licence/Sale: `Omar K. · Cashier`; nobody signed in: no person | "the person: shown where somebody is in…" |
| AC-4 admin named in Management | **gap**: Management is covered by the old `back_office_shell_test` bar tests that were removed; the person-in-Admin-Mode case is not re-tested (see report) | — |
| AC-5 sale screen says it once | one `BranchServerPill`, one branch name, one till name on Sale | "the sale screen says the connection and the branch once" |
| AC-6 Management draws no bar of its own | `till-status-bar` absent in the Management-only harness | `back_office_shell_test.dart` (Home test and the pane walk) |
| AC-7 cloud vs offline pill | sync pill vs branch-server pill | "a cloud till shows the sync state…" |
| AC-8 RTL and long names | Arabic role and mirrored layout, LTR version; long names at 1024 px with no overflow | "in Arabic…", "long names ellipsize…" |
| AC-9 fits the smallest window | Sale at 1024×700, en and ar, no overflow | "the sale screen still fits the smallest window…" |
| AC-10 dialogs | **needs a person**: bar visible and the dialog unaffected over a modal; idle lock unaffected | manual |

Regressions protected: `settings_bar_test.dart` (the bar above still builds and behaves), `admin_entry_test.dart` (its "inside the back office" marker moved from the old bar to the header, `back-office-title`).

Needs a person: a look at the running till in Arabic and English at 1024×700 on Sale and Floor (AC-9 is only "builds without overflow"), a modal open over a screen (AC-10), and macOS and Windows window chrome.

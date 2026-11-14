# Remove the dark-mode shortcut from the Settings menu — technical plan (approved 2026-10-29, recommendation; implemented, uncommitted; see TEST_REPORT.md)
Status: implemented, uncommitted · 2026-10-29 · Spec: `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section C (README XORDER-013; proposed id **XORD-040**) · Repo: `xorder-pos` only · Verified against `xorder-pos` branch `fix/receipt-merge-rounds` (= `main` `c67c754` + `934ea8d`; one unrelated uncommitted file `test/data/local_bootstrap_test.dart`). Work goes on a **new branch off `main`**.

## 1. What is there, and a correction to my earlier report
- The row is a `MenuButton` in the Settings dropdown (`lib/app/app.dart:~447-469`): "Switch to dark / Switch to light" with a moon/sun icon, calling `brightnessProvider.notifier.toggle(showing)`. The locals `showing` and `dark` (`:222-225`) exist only for it.
- **Correction.** My investigation said a cashier would lose any way to change the theme. That is wrong on the current tree: since XORD-030 (owner, 26 Oct) the window's bar, including this menu, is **not shown to a cashier at all** (`visible = managesTerminal || adminSession != null || !setupComplete`, `app.dart:~262-265`; pinned by `settings_bar_test.dart` "...MenuBar findsNothing" at ~line 410). So the row is seen only by whoever manages the terminal, anybody in Admin Mode, and anyone during first-time setup.
- Settings → Appearance already offers a **three-way** theme choice (light, dark, system) beside language (`management_appearance_pane.dart`, `AppearancePart.theme`, `brightnessProvider`), reached from the same Settings menu in Admin Mode. The row is a redundant subset of it, as the README says.

## 2. Change
1. Delete the theme `MenuButton` and the now-unused locals `showing`/`dark` in `app.dart` (the `themeMode` switch at `:50` keeps using `brightnessProvider`). The divider logic stays right: language item, then `if (managesTerminal) MenuDivider()`; no gap is left.
2. Remove the two strings `switchToDark` / `switchToLight` (abstract getter plus en and ar) — unused once the row is gone; a grep shows only `app.dart` and `settings_bar_test.dart` use them.
3. Nothing else: language switch, Orders, Printer, Reset, Appearance pane and `brightnessProvider` are untouched.

## 3. Tests (no database)
- Replace `settings_bar_test.dart` "the theme item names the theme the next tap would give" with: the Settings menu has **no** theme row in dark and in light, in English and Arabic (no "Switch to…", no moon/sun icon), and the other items are still there; no doubled divider (counted).
- Keep "and the language item flips with it" as is.
- Appearance still offers the theme: confirm an existing case in `settings_general_test.dart` covers the three choices; add one if not.
- Mutation: put the row back and confirm the new test fails.
Commands: `cd apps/xorder-pos && flutter analyze && flutter test test/features/settings_bar_test.dart test/features/settings_general_test.dart`, then the whole suite. Known unrelated failure to expect: `excel_export_test` (XORD-039, date-dependent).

## 4. Impact and risk
- Who notices: the owner/manager at the till (one fewer menu line) and the first-time setup wizard, where the menu is shown with nobody signed in: **the theme can no longer be flipped during setup** and follows the machine's theme until Appearance is reachable. Say if you want the toggle kept for the wizard only (cost: one `if (!setupComplete)`).
- Reaching the theme afterwards takes Admin Mode (hidden chord and password) → Settings → Appearance, as the README accepts.
- No server, schema, contract or permission change; nothing for `xorder-cloud`. Rollback: revert one commit.

## 5. Approvals
None of the gated kinds. **Your go is needed**, with one choice: remove it everywhere (recommended; matches the README) or keep it during first-time setup only.

## 6. Out of scope
Dropdown padding (XORDER-007), user Code length (XORDER-011), anything else on the README list.

## 7. As built (2026-10-29), and two corrections to the plan above
Branch `fix/settings-no-theme-toggle` (off `main` `c67c754`). Changed: `lib/app/app.dart` only (the theme `MenuButton` and its locals `showing`/`dark` removed; a comment says where the theme lives now) and `test/features/settings_bar_test.dart`.
1. **The strings stay.** The plan said to remove `switchToDark`/`switchToLight`. The welcome screen (`welcome_screen.dart:~140-176`) has its own corner theme toggle that uses them and `brightnessProvider.toggle`, and `test/core/localisation_test.dart` lists them. So nothing was removed from `app_strings.dart`.
2. **Setup is not left without a theme switch.** The plan worried that the theme could not be flipped during first-time setup. The welcome screen's toggle covers the start of setup; the setup wizard steps after it have none (not checked on screen).

# Consistent dropdowns — technical plan (approved 2026-10-29 with the recommendations, POS part only; implemented, uncommitted; see TEST_REPORT.md)
Status: POS implemented, uncommitted; web step not started · 2026-10-29 · Spec: README XORDER-007 (acceptance list) and `docs/harness/investigations/xorder-issues-readme-2026-10-28.md` section D, **refined below** · Proposed id **XORD-041** · Repos: `xorder-pos` (stages 1-3), `xorder-cloud` web (stage 4, only if you want it now) · Verified against `xorder-pos` `c67c754`/branch `fix/settings-no-theme-toggle`, `xorder-cloud` `775bf0f` (12 unrelated uncommitted files there). Nothing here was seen on a screen: padding differences below are read from code.

## 1. What is really there (corrects my earlier count of "about 27")
**POS** — 10 real `DropdownButton` sites (the earlier figure counted `DropdownMenuItem` lines):
| Kind | Where | How it is built | Problem |
|---|---|---|---|
| Filter chip, **3 identical copies** | `order_history_screen.dart:~1100`, `shift_history_bits.dart:~265`, `management_staff_pane.dart:~1180` | 40 px (`PosSize.filterChip`) container, 1 px border (accent when set), 8 px side padding, 12.5 px text, `isDense` | consistent with each other, but copy-pasted: the next edit will drift |
| Form field | staff editor role (`management_staff_pane.dart:~1497`), combo category (`management_combos_pane.dart:~576`), combo option product (`:~786`) | raw `DropdownButton`, `isExpanded`, **Material default underline, no frame, no padding** | sits under a `MicroLabel` next to `TextField`s that are filled with a 2 px ink border and 16 px padding (`theme.dart:105-123`), so the box looks like a different control and is shorter |
| Inline setting | terminal pane `admin-timeout`, `admin-shortcut` (`management_terminal_pane.dart:~586, 614`) | no underline, no frame, default padding | readable but unframed, unlike every other setting control |
| Table cell | staff row role (`management_staff_pane.dart:~764`) | no frame, 13 px text, `isExpanded` | deliberate in-row control; text size differs from the editor's 14 px |
Other pickers (`PopupMenuButton` in `purchase_order_dialog.dart:654`, `management_menu_pane.dart:1327`) are not dropdowns of this kind; out of scope.

**Cloud web** — 76 native `<select>` in 33 files. 52 use the one shared rule `.input` (`packages/ui/src/theme.css:136`: 10 px 13 px padding, 15 px text, 10 px radius), so the base is consistent. Variants that break it: `.fld` sets `min-height` **44 px** in two files (`AuditLogsView.vue:144`, `RestaurantForm.vue:1006`) and **46 px** in `LoginView.vue:122`; `.lib-select` (`ItemForm.vue:407`, `padding-block: 8px`); `.filter-sel` (`TablesView.vue:492`); two with a `ctl` class (definition not located). A visual check is needed to say which of these a person would call wrong.

## 2. POS design (stages 1-3, no database, no contract change)
1. **`PosDropdownField<T>`** (new, `lib/core/ui/widgets/pos_widgets.dart`): an `InputDecorator` + `DropdownButtonHideUnderline` + the same `DropdownButton<T>`; forwards `key`, `value`, `items`, `onChanged`, `hint`, `disabledHint`, `style`; `isExpanded` true by default, `dense` for inline use. Because it is an `InputDecorator` it takes the theme's frame, fill and padding from `inputDecorationTheme`, so it matches a `TextField` **by construction** and follows RTL (directional padding). The inner `DropdownButton` keeps its `Key`, so existing tests that find it are unaffected.
2. **`FilterDropdown<T>`**: the three identical copies become one widget; same pixels, same keys (`users-role-filter`, `dropKey`).
3. Use `PosDropdownField` for the 3 form fields; `dense: true` for the 2 terminal-pane settings. Leave the staff-row cell alone (open question 2).
Order: stage 2 first (pure refactor, no visual change), then stage 1+3.

## 3. Tests (all `flutter test`, no database)
- Measurement: `PosDropdownField` height equals a `TextField`'s in the same theme within 0.5 px (en and ar); text starts at the start edge and the arrow sits at the end edge (the two flip in RTL); disabled shows `disabledHint`; selecting an item calls `onChanged`.
- `FilterDropdown`: chip height 40, 1 px border (accent when set), same behaviour as the copies (existing `order_history_test`, `shift_history_panes_test`, users filter tests).
- The existing tests that use the keys `staff-editor-role`, `combo-category`, `combo-option-product-*`, `admin-timeout`, `admin-shortcut` still pass.
- Mutation: drop the `InputDecorator` and confirm the height test fails.
- There are no golden files in the project, so **a person must look** at the three dialogs and the filter bars at 1440×900 in Arabic and English; I will list the screens.
Commands: `cd apps/xorder-pos && flutter analyze && flutter test`, whole suite. Known unrelated failure: `excel_export_test` (XORD-039).

## 4. Web (stage 4; separate, and only after you have seen stages 1-3)
Pick one height for `.fld` (44 or 46) and put it in `packages/ui/src/theme.css` once instead of three page-local rules; leave `.lib-select` and `.filter-sel` (intentional compact variants) unless you say otherwise. No JS test framework exists: verification is `pnpm build` plus a person looking. Any push to `xorder-cloud` `main` deploys to production: I would only commit locally on a branch, and `/release-check` comes before you push.

## 5. Approvals
None of the gated kinds for stages 1-3 (UI only). **Your go is needed.** Decisions:
1. Form dropdowns take the text-field look (2 px ink border, filled, 16 px padding): recommended, so a form's controls match.
2. Leave the staff-row role cell as it is (in-row control): recommended.
3. Do the web step now or after you look at the POS result? Recommended: after, and then 44 or 46?

## 6. Out of scope
Keyboard navigation of the Back Office menu dropdowns (XORD-022-E is about the top-bar menus, a different component), the user Code length, anything else.

## 7. As built (2026-10-29) — POS only
Branch `fix/dropdown-consistency` (off `main` `c67c754`). Files: `lib/core/ui/widgets/pos_widgets.dart` (new `FilterDropdown<T>` and `PosDropdownField<T>`, appended; nothing else in the file touched), `order_history_screen.dart`, `shift_history_bits.dart`, `management_staff_pane.dart` (the three private filter copies removed; the staff editor's role dropdown), `management_combos_pane.dart` (category and option product), `management_terminal_pane.dart` (timeout and shortcut). Tracker id **XORD-041**.
Two things the plan did not foresee: (1) an input frame cannot have an unbounded width, so the inline variant (`expanded: false`) is wrapped in `IntrinsicWidth` (caught by the measurement test); (2) `InputDecoration.isDense` must be set for the compact frame to get under the 48 px minimum. Decisions as recommended: form dropdowns take the text-field look; the staff-row role cell is untouched; the web step waits until you have looked at this.
**Screens a person must look at** (no golden files exist): Users → Add/Edit user (role); Menu → Combos → New/Edit combo (category, each option's product); Settings → Terminal (admin timeout, admin shortcut); Order history, Shift history and Users filter bars; each in English and Arabic at 1440×900.

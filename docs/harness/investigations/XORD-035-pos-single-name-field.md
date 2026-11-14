# XORD-035 (proposed id) — POS name forms show two name fields; the language chosen in the setup wizard never reaches the "menu languages" setting that decides it

Status: investigated · 2026-10-27 · Confidence: **confirmed** for the cause and the reproduction; **likely** for the proposed fix shape (it depends on the decisions in section 9) · Verified against: `xorder-pos` `5cf13cc` + uncommitted changes from other work (not mine; none of the files that decide this behaviour carry a diff touching content languages) · `xorder-cloud` `775bf0f` (read only, for the `bilingual` default).

The id is proposed: `docs/qa/XORDER_QA_FINDINGS.md` currently ends at XORD-034, so the next free one is XORD-035. I did not add it to that file (investigation only). This is a *behaviour change that contradicts a shipped design* (XORD-005 / XORD-023), not a plain defect; see section 3 and 9.

## 1. Symptom

- App: `xorder-pos`, offline (branch-server) install. Back Office → Menu → Categories → "Add category".
- Steps: finish the setup wizard (language screen: Arabic or English), open Back Office, add a category.
- Actual: **two** name boxes — `Name` and `Name in Arabic · optional` — whichever language the wizard chose. Same on item, unit and the other dialogs listed in section 5.
- Expected (ticket): one box, labelled and aligned in the language chosen in the wizard (`الاسم`, RTL, right-aligned / `Name`, LTR, left-aligned); no translation ever required.

## 2. How it was reproduced

Existing suites first (baseline, current tree):

```
cd apps/xorder-pos && flutter test test/features/content_languages_forms_test.dart \
  test/features/content_languages_dialogs_test.dart test/features/content_languages_card_test.dart \
  test/features/units_pane_test.dart test/core/localisation_test.dart
→ 00:08 +89: All tests passed!
```

So the *present* design (three "menu languages") is correctly implemented and tested; the tests assert `both` shows two fields (`content_languages_forms_test.dart:~205` "both: two fields").

Throwaway widget test (scratchpad only, `scratchpad/repro/test/repro_test.dart`, a separate package depending on `xorder_pos` by path; nothing was added to either repo). It opens the real `ManagementMenuPane` → "Add category" with the real `contentLanguagesProvider` (not overridden, i.e. what a till with no setting stored resolves to) and with each override. Real output:

```
REPRO[fresh-install UI=ar content=<unset -> both>] fields=2 textDirections=[null, TextDirection.rtl] textAligns=[start, start] texts=[قسم جديد, الاسم, الاسم بالعربية · اختياري, إلغاء, حفظ]
REPRO[fresh-install UI=en content=<unset -> both>] fields=2 textDirections=[null, TextDirection.rtl] textAligns=[start, start] texts=[New category, NAME, NAME IN ARABIC · OPTIONAL, Cancel, Save]
REPRO[UI=en content=ar] fields=1 textDirections=[TextDirection.rtl] texts=[New category, NAME, Cancel, Save]
REPRO[UI=ar content=en] fields=1 textDirections=[null] texts=[قسم جديد, الاسم, إلغاء, حفظ]
REPRO[UI=ar content=ar] fields=1 textDirections=[TextDirection.rtl] texts=[قسم جديد, الاسم, إلغاء, حفظ]
00:01 +5: All tests passed!
```

(`NAME` is upper-case because `MicroLabel` upper-cases; the string is `Name`.) The first two lines are the reported symptom. The third and fourth show the second defect in section 3(c).

Not done: I did not run the app on a real PostgreSQL or look at the screen (no database; widget-level evidence only).

## 3. Root cause

Three separate mechanisms, in order of importance.

**(a) Cause of the two fields — the wizard language is never connected to the setting that decides the fields.**
- The category dialog asks `ContentLanguages` (`ar | en | both`), read from `pos_restaurants.content_languages` (`lib/app/providers.dart:1305-1321`, `contentLanguagesNowProvider` `:1396-1398`; dialog `lib/features/admin/presentation/management_menu_pane.dart:657-733`, fields shown by `languages.showsEnglish / showsArabic`).
- That column is `NOT NULL DEFAULT 'both'` (`lib/data/postgres/migrations.dart:4586-4603`).
- An offline install creates its restaurant row with `INSERT INTO pos_restaurants (slug, name)` (`lib/data/postgres/local_bootstrap.dart:359`) — no `content_languages`, so it is `both`.
- The wizard's language choice (`SetupDraft.locale`, `setup_panes.dart:244-275`) is written only to the terminal's config file (`setup_controller.dart:1107`, `SavedTerminalConfig.languageCode`) and the in-memory locale (`:1122`). Grep of `lib/features/setup` and `local_bootstrap.dart` finds **no** reference to `ContentLanguages` / `content_languages`.
- The only way to leave `both` is a manager finding Settings → Appearance → "Menu languages" (`management_appearance_pane.dart:55-120`), which nobody told them about.
- Fallbacks reinforce it: provider returns `both` while loading, with no database and for a null value (`providers.dart:1309,1319,1398`; `ContentLanguages.fromWire`, `content_languages.dart`: unknown → `both`, documented as "the safe way to be wrong").

**(b) Contributing: the design deliberately separates content language from interface language.** `content_languages.dart` header: "**This is content, not the interface.** The till's own language … says nothing about it", and XORD-005 / XORD-023 in `docs/qa/XORDER_QA_FINDINGS.md` say the same for the cloud dashboard. The ticket's business rules 1–3 ("the POS operates in a single selected language … the selected language must control the form labels, text direction and input alignment") reverse that for the POS. This is a product decision to confirm (section 9, Q1), not an oversight.

**(c) Second defect, independent of the above: direction and label follow different languages.** `MenuInput` forces RTL whenever `arabic: true` (`menu_editor_widgets.dart:176-180`, `_direction`), and the label is the *screen's* string `fieldName`. Result (rows 3–4 of the output): English screen + Arabic content = label `Name` over an RTL box; Arabic screen + English content = `الاسم` over a box with direction `null`, i.e. it inherits the screen's RTL for English text. The ticket's rule "direction and alignment follow the selected language" is therefore not met even in the single-language modes. Alignment: `TextAlign.start` everywhere, which is right-aligned only when the box's directionality is RTL.

**Symptom vs cause.** Symptom: two boxes. Cause: (a). (b) is why nobody wired (a). (c) is a latent fault that becomes visible the moment (a) is fixed by the obvious route.

## 4. Evidence and alternatives ruled out

- *"The dialog ignores the setting"* — ruled out: widget tests and my repro show `ar` / `en` yield one field.
- *"Cloud bundle forces `both`"* — real for cloud restaurants (`Restaurant.bilingual` defaults `true`, migration `2026_07_01_000100_add_bilingual_to_restaurants_table.php:14`; `ContentLanguages::fromPlatform` → `both`), but **not the path in this ticket**: the menu pane is offline-only (`management_menu_pane.dart:28`, repositories refuse writes when `!offline`, `postgres_catalog_admin_repository.dart:76,626`). A cloud till never opens these dialogs for authoring. So the reported install is offline.
- *"Stored names would be lost"* — ruled out: `resolveNames` (`content_languages.dart`, tested in the 61-case `content_languages_dialogs_test.dart`) never blanks the hidden language and mirrors `name_en` for Arabic-only because **`name_en` is NOT NULL in the till's database**.
- Not verified: the rendered screen, PostgreSQL behaviour, Windows.

## 5. Impact

Forms that ask for a second-language name and honour `ContentLanguages` today (all of them show two boxes on a default install): category, item (`management_menu_pane.dart`), combo (`management_combos_pane.dart`), extras / size groups and their option rows (`management_extras_pane.dart`), unit (`unit_dialog.dart`), tax group, service charge, tender type, order type, stock item, supplier. A sweep for `fieldNameArabic | arabic: true | _nameAr | name_ar` under `lib/features` finds **no other** form and no form outside this set; `financial_account_dialog.dart` already has a single `name`. The menu import (`lib/domain/services/menu_import.dart`) reads a `name_ar` column and is a data door, not a form (not changed by this ticket, but it can create records whose only name is English or Arabic — see Q4).

- Venue models: all four. Cafés/food trucks (one till, one language) feel it most; a restaurant with two tills in different languages is the risky case (section 6, risk R1).
- Data already wrong: none. Every offline install already holds `content_languages = 'both'` and rows with whatever names were typed; that is valid data.
- Read side is unaffected: `Category/Product.displayName(locale)` shows `nameAr` for an Arabic screen when present, else `nameEn` (`catalog.dart:95-98`).
- No money, tenant, permission or order-state surface. Not routed to `/security-audit`.

## 6. Fix options

Narrowest first. None touches money, order state or the API.

**Option A — make the wizard set the setting (and stop defaulting to `both`) — recommended base.**
1. On offline setup, after the restaurant row is seeded, write `content_languages` = `ar` or `en` from `SetupDraft.locale` (`setup_controller.dart` finish step + `local_bootstrap.dart:359` insert, or pass the value into `seedRestaurant`). Needs the same admin credential the seed already uses.
2. Existing installs sitting on `both`: either leave them (they keep two boxes until a manager picks one in Appearance — contradicts "apply consistently") or one-time set them from the terminal's stored language at next start (a data write on populated rows → needs approval and a note that it is per-restaurant but the language is per-terminal; see R1). Hiding the `both` option in the Appearance card must be decided with it (Q2).
3. Fix (c): `MenuInput` direction/alignment from the *chosen* language, and the single label from the same language. The label strings already exist (`fieldName` = `Name` / `الاسم`).
- Trade-off: smallest and reuses the fully tested `resolveNames`/hidden-field-preservation machinery; keeps the content-vs-interface separation, so the field follows the *setting*, not the live language switch.

**Option B — derive the visible language from the live terminal locale (ticket wording: "selected language").** `contentLanguagesNowProvider` returns `ar`/`en` from `localeProvider`; the stored setting is ignored for the forms.
- Trade-off: simplest to explain, but the locale is **per terminal and switchable any time** (`app.dart:437-448` bar switch, Appearance language row, persisted to the terminal config file) while the menu is **per restaurant** on a shared branch database. A cashier toggling the bar to English opens an English-only form on an Arabic menu; two tills in different languages write to different columns of the same row. `resolveNames` stays safe (nothing is erased), but the same restaurant's rows would be authored in whichever language the last till used. Only choose this if Q1 says the language is truly per till.

**Option C — also remove `both` from the model.** Delete the enum value, the Appearance card and the platform mapping. Largest diff, touches the cloud bundle contract (`bilingual`) and ~11 dialogs; not needed for this ticket. Not recommended now.

Must NOT change: the `name_en NOT NULL` rule and `resolveNames` semantics; stored translations (never blanked or deleted); the bundle contract (`bilingual`, `default_language` stay additive); `displayName` fallbacks; the cloud dashboard (separate ticket, XORD-023).

## 7. Tests the fix needs

New regression tests (would have caught this):
1. *Setup → setting*: finishing offline setup with locale `ar` stores `content_languages = 'ar'`, with `en` stores `'en'` (unit test on the seeding path; PostgreSQL-tagged, self-skips without `POS_PG_HOST`; run via `scripts/check.sh`).
2. *Default dialogs*: with the provider **not overridden** after a wizard-created restaurant, each of the 12 forms in section 5 shows exactly one name box (extend `content_languages_dialogs_test.dart` / `content_languages_forms_test.dart`, which today only assert overridden values).
3. *Direction, alignment, label*: for each of Arabic and English, assert `TextField.textDirection`, the label string and `TextAlign` of the single box (the cases in my repro, as assertions: `UI=en`+`ar` content must not be RTL under a `Name` label, and vice versa).
4. *Create/edit parity* and *validation*: empty name refused in both modes; edit of a row with both names keeps the hidden name; edit of a row that has only the other language's name opens with that name visible, not an empty box (see Q4).
5. *Existing data*: a record created under `both` with two names, opened after switching to `ar` and to `en`, loses nothing on save (already covered by `resolveNames` tests; add one end-to-end on the category dialog).

Existing suites to run: the five listed in section 2, `test/features/combos_ui_test.dart`, `menu_import_ui_test.dart`, `test/data/*` suites touching `pos_restaurants`, then `flutter analyze` and `scripts/check.sh`.

## 8. Approvals the fix needs

- Product decision (Q1, Q2) before planning.
- A one-time rewrite of `pos_restaurants.content_languages` on existing installs (Option A.2) is a data change on populated rows: approval required; additive and reversible (a value in an existing CHECK-constrained column), no schema change, no migration needed otherwise. PostgreSQL behaviour cannot be proven by the SQLite cloud suite and is not in scope there.
- No cloud change, no contract change, nothing reaches `xorder-cloud` `main`. Rollout: POS only.

## 9. Open questions and what could not be verified

- **Q1 (blocking).** Is "the selected language" the restaurant's language chosen at setup (stored once, one setting for all tills — Option A), or each terminal's live interface language (Option B)? The shipped design and XORD-005 say the former is separate from the latter. A restaurant with one Arabic-menu till and a cashier who prefers an English screen is the case that decides it.
- **Q2.** Should the Appearance "Menu languages" card keep the `Arabic and English` choice? The ticket says there is no bilingual POS; keeping the option contradicts rule 2 and the dashboard still offers `bilingual`.
- **Q3.** Existing offline installs on `both`: migrate them silently to the terminal's language, or leave them and tell the manager? (Rule 5 is satisfied either way for *data*; this is about the *form*.)
- **Q4.** A row whose only name is in the *other* language (e.g. imported, or created while `en` and now viewed as `ar`): the single box would open empty. Proposal: prefill with the other-language name as a fallback; saving then writes the active language and keeps the other. Needs owner confirmation (it can show English text in an RTL box).
- **R1 (risk).** Language is per terminal, content is per restaurant; the ticket does not say what happens with two tills in two languages.
- Not verified: rendered appearance, Windows build, a real PostgreSQL run, whether any installed till has a `content_languages` set by a manager (cannot be known without the owner's server; I did not touch any database).
- Docs: `docs/features/content-languages/FEATURE.md` describes the three-way design as final (XORD-005 marked implemented); it would need an as-built update after any of the options. The inventory rows `menu-categories` and `units` are `pending` / UNVERIFIED, so there are no per-feature docs for the category and unit forms to check against.

Next action: answer Q1–Q3, then `/implement docs/harness/investigations/XORD-035-pos-single-name-field.md`.

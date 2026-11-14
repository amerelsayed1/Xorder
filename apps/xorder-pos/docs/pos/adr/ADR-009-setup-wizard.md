# ADR-009 — Technician-led setup UX

**Status:** Accepted direction; flow still to validate. Technical design: Proposed.
**Source:** case report ADR-009; evidence `discovery/CURRENT_SETUP_WIZARD.md`.

## Context

The wizard is one 12-member `SetupStep` enum with three visible paths (cloud main, offline main, child).
Arabic is already the default. A Language step exists only on the offline path and does not change
the screen; the menu-bar toggle can be overwritten at completion.

## Decision (accepted rules)

- **Technician setup.** Arabic is the default locale on first launch.
- **No language-selection step.** Language lives in **Settings → General → Language**, available
  during the wizard and after; the preference persists before a database exists.
- UI paths are **conditional on plan and primary/child role**; fields grouped and legible; sensitive
  actions need explicit verification.
- No fixed nine-screen requirement for every path.

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| `SetupStep` has 12 values; `visibleSteps` picks one of three lists: cloud main 4–6, offline main 10–11, child 7 | `setup_state.dart:26, 264, 305, 320, 342` |
| Default locale Arabic for a fresh till and the wizard draft | `providers.dart:1859`, `setup_state.dart:85` |
| **Language step (offline only) writes `SetupDraft.locale` but does not switch the screen**; applied at `complete()` | `setup_controller.dart:301, 904`; `setup_panes.dart:235-271` |
| **Menu-bar toggle calls `localeProvider.apply` without touching the draft; `complete()` then saves `draft.locale`** → toggle lost | `setup_controller.dart:106, 889, 904`; `app.dart:386-398` |
| Language switch exists in three places; none is "General Settings"; `settingsGeneral` titles the **receipt** pane | `management_appearance_pane.dart:62-89`, `management_screen.dart:952` |
| `localeProvider.apply` persists to `config.json` only if the file exists — nothing persists during the wizard | `providers.dart:1895-1904` |
| Saved config without `language` reads as `en` (disagrees with the Arabic default) | `terminal_config.dart` (`?? 'en'`) |
| Offline path never reads `install-credentials.json`; only the cloud claim does | `setup_controller.dart:1521, 1678` |
| Only the cloud claim is resumable (`setup-progress.json`); offline loses licence and form input on kill | `setup_controller.dart:207-299` |
| Offline/child `registerManually` inserts a new `pos_terminals` row every run (R-DUP-1) | `postgres_directory_repositories.dart:240-254` |
| Settings bar (incl. language) disabled on `/welcome`; wizard has hard-coded `Alignment.centerLeft` in 7 places | `app.dart:~488-492`; `setup_panes.dart:483,598,…` |

## Gaps

- No General Settings home for language; wizard language timing defects (two).
- Offline progress not durable; duplicate terminal rows (fixed by P0-4).
- Installer credential handoff not used on the offline path.
- Step count not yet validated against the accepted case matrix.

## Proposed design (not yet approved)

- **Remove the Language step**; add **Settings → General → Language** pane (reuse `localeProvider` +
  `TerminalConfigStore`); the wizard header carries the same control. `localeProvider.apply` writes a
  small `locale.json` (or the config stub) **before** a database/config exists so the choice survives
  restart; `complete()` reads the live locale, not a stale draft.
- Fix the fallback: absent `language` in a saved config → `ar`.
- **Offline path reads `install-credentials.json`** when readable (same as cloud), falling back to
  manual fields.
- **Durable offline progress** via `SetupProgressStore` including the registered `terminalId` (P0-4);
  resume revalidates the DB and device; never re-registers.
- Dynamic step count per the case matrix:

| Case | Screens (conditional) |
|---|---|
| Cloud primary | Licence → plan confirmed → pair/sign-in → provision & verify DB → device/peripherals → summary |
| Offline primary | Licence → local host/DB → owner/bootstrap → branch → device → hardware/money/menu checks → external backup destination → summary |
| Child LAN till | Find/enter primary host → verify site licence and manager → select branch → register till → peripherals → summary |
| Locale change | Settings → General → Language → applies immediately, persists |
| Interrupted offline setup | Resume from checkpoint; no duplicate terminal row |
| Failed DB initialisation | Diagnostic + retry of the safe step; no implicit destructive reset |

- Replace physical `Alignment.centerLeft` with `AlignmentDirectional`; mono fields (URLs, hosts) get LTR.

## Acceptance tests

- Correct dynamic step count/navigation per plan and role.
- RTL Arabic default; English LTR across the full app; mono fields LTR in Arabic.
- Preference survives restart before a configured DB; toggle during the wizard is what gets saved.
- No owner/database/terminal duplicates on re-run; step recovery after a kill.
- No credentials in diagnostics; installer credential handoff used by both paths.

## Open questions

- GAPS §5 **Q23** (where General Settings is — accepted), **Q24** (Arabic-Indic vs Western digits;
  receipt language rules), **Q25** (offline wizard reads installer credentials — accepted here).
- Case report: updated wireframes after code validation; installer's PostgreSQL responsibility;
  auto-select plan when the licence permits both; device-specific settings and permission gates.

## Related roadmap phase

**P0-4** then **Phase 6**. See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).

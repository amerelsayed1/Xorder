# Feature changelog: Login, session token and password change

## 2026-10-20 — documentation created
- Status: documented from the existing implementation (no code change), batch 1 of the documentation plan.
- Changes: initial FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG.
- Compatibility notes: none; documentation only.
- Verification: mechanical citation check (`scripts/harness/check-citations.py`) and author spot-checks of load-bearing claims against source; independent passes are recorded in the later entries below. Tests: not run for this feature (see TEST_REPORT).

## 2026-10-20 — independent pass fixes
- batch-1 qualifying pass fixes: POS token use described per flow (with the divergence from the one-call comment), request-level username uniqueness, SQLite-only index re-creation, narrowed ledger absence claim, sessions wording, N-class citations and test attributions. Status stays `drafted`; see `docs/validation/2026-10-20-batch1-p0-qualifying-passes-report.md`.

## 2026-10-20 — second independent pass fixes
- audit sink wording, POS token use in `API.md`, contract line numbers, DATABASE citations, five absence rows. Status stays `drafted`; see `docs/validation/2026-10-20-batch1-round2-qualifying-passes-report.md`.

## 2026-10-20 — third independent pass fixes
- Fixes from the round-3 findings (see `docs/validation/2026-10-20-batch1-round3-qualifying-passes-report.md`). Status stays `drafted`.

## 2026-10-20 — fourth independent pass fixes
- Fixes from the round-4 findings (see `docs/validation/2026-10-20-batch1-round4-qualifying-passes-report.md`). Status stays `drafted`.

## 2026-10-20 — fifth independent pass fixes
- Fixes from the round-5 findings (see `docs/validation/2026-10-20-batch1-round5-qualifying-passes-report.md`). Status stays `drafted`.

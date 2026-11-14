# Feature changelog: Roles, capabilities and gates

## 2026-10-20 — documentation created
- Status: documented from the existing implementation (no code change), batch 1 of the documentation plan.
- Changes: initial FEATURE, TECHNICAL, API, DATABASE, TEST_PLAN, TEST_REPORT, CHANGELOG.
- Compatibility notes: none; documentation only.
- Verification: mechanical citation check (`scripts/harness/check-citations.py`) and author spot-checks of load-bearing claims against source; independent passes are recorded in the later entries below. Tests: not run for this feature (see TEST_REPORT).

## 2026-10-20 — independent pass fixes
- batch-1 qualifying pass fixes: bootstrap freshness facts (analysis I, J), ungated shell endpoints, `Role` auditing, contract-ledger mentions (POS-BE-002, POS-BE-030), compatibility inference moved to analysis K. Status stays `drafted`; see `docs/validation/2026-10-20-batch1-p0-qualifying-passes-report.md`.

## 2026-10-20 — second independent pass fixes
- BR-4/AC-3 scope, DELETE body, pulse null, enum tests, AC-6, 33 tests, ungated PIN routes, services enforcing `pos.*`. Status stays `drafted`; see `docs/validation/2026-10-20-batch1-round2-qualifying-passes-report.md`.

## 2026-10-20 — third independent pass fixes
- Fixes from the round-3 findings (see `docs/validation/2026-10-20-batch1-round3-qualifying-passes-report.md`). Status stays `drafted`.

## 2026-10-20 — fourth independent pass fixes
- Fixes from the round-4 findings (see `docs/validation/2026-10-20-batch1-round4-qualifying-passes-report.md`). Status stays `drafted`.

## 2026-10-20 — fifth independent pass fixes
- Fixes from the round-5 findings (see `docs/validation/2026-10-20-batch1-round5-qualifying-passes-report.md`). Status stays `drafted`.

# Feature changelog

## 2026-10-26 — VAT box moves the default tax group (XORD-027)
- Status: implemented (POS, offline tills); tests run, see TEST_REPORT.md; not committed
- Changes: `saveMoneyConfig` also sets the default tax group's rate in the same transaction, refuses a rate over 100%, audits the group's rate before and after (`apps/xorder-pos/lib/data/postgres/postgres_catalog_admin_repository.dart`); Taxes pane shows the default group's rate and re-reads the groups after saving (`management_taxes_pane.dart`); cart VAT label shows the applied rate and no longer rounds fractions (`cart_panel.dart`).
- Why: a ticket is taxed at the default group (seeded at 14% by every offline setup), so the VAT box (`vat_bp`) had no effect: a till set to 0 still charged and printed 14%. Root cause: docs/harness/investigations/vat-box-zero-still-charges-14-and-inclusive-option.md.
- Compatibility notes: no schema, migration, API or cloud change; no stored value rewritten; tills where the box and the group already disagree keep charging the group's rate and the box now shows it.
- Verification: see TEST_REPORT.md.
- Documentation: this folder created on this date (first documentation of `tax-rules`; partial scope, see FEATURE.md).

## Unreleased
- Status: planning
- Changes: XORD-028 tax-inclusive switch and cloud `tax_mode` (not started; needs a specification).
- Compatibility notes: additive bundle key, cloud deployed first.
- Verification: not run

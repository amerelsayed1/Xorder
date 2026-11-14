# Database — pos-signin-first-home

No schema change, no migration, no new column or index (verified 2026-10-27 against the touched files). Existing tables read or written exactly as before: `pos_shifts` (opened from Home with the same repository call), `pos_business_days` (opened with the first shift; closed by the day-close dialog, `closed_by` now taken from the acting person), `pos_audit` (`shift.opened`, `day.closed`, `day.force_closed` as before). Sign-in writes nothing. PostgreSQL behaviour of a day close with no shift open was not run (fakes only); see `TEST_REPORT.md`.

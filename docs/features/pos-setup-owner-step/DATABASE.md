# Database — pos-setup-owner-step

No schema change, migration, column or index (verified 2026-10-27). The bootstrap writes exactly what it did before (database, till role, schema, restaurant, branch, roles, reasons, tax group, tenders, order types, first owner, grants). The only data change is in memory: the PIN confirmation and which of the two screens shows are not persisted (`setup_progress_store.dart` still stores only the step and `bootstrapped`). PostgreSQL behaviour of the build is covered by the PostgreSQL-tagged `installer_owner_test`, which was **not run** here.

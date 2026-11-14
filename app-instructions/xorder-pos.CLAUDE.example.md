# xorder-pos scoped instructions (reference — verified 2026-10-20)

`apps/xorder-pos/CLAUDE.md` already exists and is authoritative; this file is only a harness cross-reference. Do not copy it over the repo's own file.

- Stack: Flutter 3.47 / Dart 3.13, Riverpod, go_router, `postgres` (pure Dart) against a branch PostgreSQL, `dio` for the cloud.
- Verification: `flutter analyze`, `flutter test` (green without a DB; `integration` tags self-skip without `POS_PG_HOST`), `scripts/check.sh` (needs local PostgreSQL).
- Money is integer minor units; all ticket/money rules live in `lib/domain/services/ticket_engine.dart`; DI seam is `lib/app/providers.dart`.
- Offline-first exists (outbox in `pos_outbox`, `lib/data/cloud/outbox_drain.dart`); never assume a cloud contract is deployed unless `docs/coordination/BACKEND_TO_POS.md` marks it `READY`.

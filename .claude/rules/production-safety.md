# Production safety

- `xorder-cloud` `main` is live: push → CI API tests → auto-deploy to https://xorder.io → migrations applied to production PostgreSQL. Treat every commit that could reach `main` as a production change. Claude never pushes, merges, tags or deploys; the user does, after `/release-check`.
- Migrations must be additive and non-destructive (no drops/renames/type changes of populated columns without an approved multi-step plan). Cloud tests run on SQLite and cannot prove PostgreSQL behavior: review locks, indexes and constraints by reading, and say so.
- Never run `migrate:fresh`, `migrate:rollback`, `db:wipe`, restore or dump commands. Never touch `db-backups/`.
- Cloud and POS deploy independently: contract changes are additive, and the rollout order is written down before implementation.

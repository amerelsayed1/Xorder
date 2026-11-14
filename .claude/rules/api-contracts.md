---
paths:
  - "apps/xorder-cloud/apps/api/routes/**"
  - "apps/xorder-cloud/apps/api/app/Http/Controllers/Pos/**"
  - "apps/xorder-cloud/apps/api/app/Http/Resources/**"
  - "apps/xorder-cloud/apps/api/app/Http/Requests/Pos/**"
  - "apps/xorder-cloud/packages/api-client/**"
  - "apps/xorder-pos/lib/data/cloud/**"
  - "apps/*/docs/coordination/**"
---

# Laravel ↔ Vue ↔ Flutter contracts

- Provider: `apps/xorder-cloud/apps/api/routes/api.php` (POS routes in the `pos` groups; controllers `app/Http/Controllers/Pos`, shapes `app/Http/Resources`, validation `app/Http/Requests/Pos`). There is **no `/v1` prefix**: compatibility is managed by additive-only changes and the coordination ledger.
- Consumers: POS `apps/xorder-pos/lib/data/cloud/` (`cloud_api.dart`, `cloud_sync.dart`, `outbox_drain.dart`, `branch_sales_api.dart`); Vue `apps/xorder-cloud/packages/api-client` and `apps/*/src`.
- Ledger: `docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND,BACKOFFICE_TO_CLOUD}.md` exists in **both** repos (`BACKEND_TO_POS.md` is owned by the cloud side; copies drift, compare before relying on one). Integrate only against `READY` items; keep fakes for the rest. When a `POS-BE-xxx` ships, flip its row to `READY` with the final contract.
- Any change: document request/response, auth (JWT bearer / device token), errors, pagination, optional fields, idempotency keys and backward compatibility in `docs/features/<slug>/API.md`, then `/project-documentation update <slug>`. Prefer additive fields; never silently change a response shape. Cloud and POS deploy independently, so the POS must tolerate old and new servers during rollout: write the rollout order (usually cloud first, POS after).
- Add consumer/provider checks where feasible: cloud Feature tests asserting response shape; POS tests with `lib/data/fakes`.

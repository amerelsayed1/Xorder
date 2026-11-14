---
name: api-contracts
description: Coordinate Laravel-Vue-Flutter interfaces and compatibility.
---

# Api Contracts

## Procedure
0. Start from the knowledge layer: `/project-documentation context <slug> plan` (the feature's `API.md`, contract IDs and status in `docs/FEATURE_INVENTORY.md`, cross-application dependencies), then verify against the source below.
1. Locate the provider side: `apps/xorder-cloud/apps/api/routes/api.php` (POS routes under the `pos` groups; controllers in `app/Http/Controllers/Pos`, shapes in `app/Http/Resources`, validation in `app/Http/Requests/Pos`). There is **no `/v1` URL prefix**, so compatibility is managed by the coordination docs and additive-only changes.
2. Locate consumers: POS `apps/xorder-pos/lib/data/cloud/` (`cloud_api.dart`, `cloud_sync.dart`, `outbox_drain.dart`, `branch_sales_api.dart`); Vue `apps/xorder-cloud/packages/api-client` and `apps/*/src`.
3. Read the contract ledger: `docs/coordination/{BACKEND_TO_POS,POS_TO_BACKEND,BACKOFFICE_TO_CLOUD}.md` in **both** repos (copies can drift — `BACKEND_TO_POS.md` currently differs). Integrate only against `READY` items; keep fakes for the rest.
4. Document request/response, auth (JWT bearer / device token), errors, pagination, optional fields, idempotency keys and backward-compatibility in `docs/features/<slug>/API.md` (then `/project-documentation update <slug>` to refresh the inventory). Prefer additive fields; deploys are independent, so the POS must tolerate old and new servers during rollout. Write a rollout order (usually cloud first, POS after).
5. Add consumer/provider checks where feasible (cloud Feature tests asserting response shape; POS tests with `lib/data/fakes`).

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.

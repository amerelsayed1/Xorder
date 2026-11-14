# XOrder POS — Existing Implementation Discovery (read-only audit)

**Date:** 2026-10-24 · **Branch:** `ccr-9c1f5618-v38ivr` · **Method:** static reading of `amerelsayed1/xorder-pos` (122 commits, ~273 `lib` files, 252 test files).
No application code, schema or migration was changed or run. No secrets are reproduced.

## Evidence limits (read first)

* **Not observed, only read.** The audit sandbox had no Flutter/Dart SDK and no PostgreSQL server. Every finding is `[CODE]`; none is `[OBSERVED]`. Tests were read and are described as "exists, not executed here". `PROJECT_REVIEW.md`'s "213 passed" is the author's claim.
* **Backend not available.** `Xorder-Menus` is an empty repository. The Laravel API, Vue admin and cloud services are **UNKNOWN**; only the POS's client calls are visible. `docs/coordination/*` records agreements, not behaviour.
* Status labels: IMPLEMENTED · PARTIAL · NOT_IMPLEMENTED · UNKNOWN.

## Documents

| Doc | Contents |
|---|---|
| [CURRENT_ARCHITECTURE.md](CURRENT_ARCHITECTURE.md) | Components found/not found, layering, communication, data ownership, docs-vs-code conflicts |
| [OPERATING_MODELS.md](OPERATING_MODELS.md) | Plan A / Plan B against code; the 10 questions; data flow per mode |
| [DATABASE_AND_SYNC.md](DATABASE_AND_SYNC.md) | PostgreSQL, migrations, outbox, idempotency, conflicts, backup/restore, crash recovery, data-loss scenarios |
| [MULTI_DEVICE.md](MULTI_DEVICE.md) | Real topology (Mermaid), pairing, auth, concurrency, device limits |
| [LICENSING.md](LICENSING.md) | Ed25519 licences, activation, offline files/keys, binding, tamper analysis |
| [CURRENT_SETUP_WIZARD.md](CURRENT_SETUP_WIZARD.md) | Every wizard step, persistence, interruption recovery, Arabic/English localisation |
| [FEATURE_INVENTORY.md](FEATURE_INVENTORY.md) | Sales floor + back office features with status and tests |
| [SECURITY_AND_RECOVERY.md](SECURITY_AND_RECOVERY.md) | Secrets, roles, TLS, PINs, SQLi review, backup security, recovery, risk register |
| [GAPS_AND_OPEN_QUESTIONS.md](GAPS_AND_OPEN_QUESTIONS.md) | Plan A/B gap matrix, risks, 31 product-owner questions, discussion order |

## A. What already works (code-supported)

* Offline-capable selling against local PostgreSQL: a sale, lines, payments, stock issue and its outbox row commit in **one transaction**, idempotent on `(restaurant_id, client_transaction_id)`; invoice numbers from a row lock.
* Integer-minor-unit money engine with half-up rounding once per tax rate; split payments; discounts/refunds/voids with limits, reasons, supervisor approval, DB triggers.
* Two deployment modes (`cloud` = Plan A, `offline` = Plan B) exist; cloud mode has outbox drain, bootstrap, heartbeat, pairing.
* Ed25519 licence verification (fail-closed release builds), vendor CLI issuer.
* Role-separated DB users, parameterised SQL (no injection found), PBKDF2 PIN hashing, append-only audit by grant + trigger.
* Setup wizard (12 steps, three paths), Arabic default UI, 1,904 strings in both languages (compile-enforced).
* Suppliers / purchase orders / receiving / supplier invoices; spreadsheet menu import; shifts and cash movements; local reports.

## B. Partially implemented

Cloud sync (no stock/voids; no conflict resolution beyond error-code classification) · offline licence (verifier exists, **no UI to import**) · backups (day-close/manual only, same disk) · multi-till LAN (shared DB, no discovery/failover/TLS by default) · device limit (child-registration only) · order lifecycle (PAID/VOIDED only) · inventory (no BOM/stocktake) · language switch (exists, no "General Settings" home; wizard timing defect) · ETA e-invoicing (pending docs only) · cloud-tills back office (signpost only).

## C. Missing

In-place plan switching · offline activation keys / offline renewal · automatic scheduled & off-box backups · server failover · kitchen ticket/KDS · delivery workflow · table merge/transfer/split-bill · card terminal integration · stock sync · crash reporting/diagnostics/support bundle · auto-update · OS keystore secret storage · transactional conflict policy · quarantine release tooling · business-day opening.

## D. Critical risks

Data: restore discards unsent sales; 2xx non-JSON marks orders delivered; stuck outbox rows have no release path; backups on same disk. Security: plaintext `secrets.json`; 4-digit PINs + no cashier lockout; plaintext LAN DB traffic with one shared role; Dart-side-only permissions; licence cache/clock tamper. Availability: DB host down ⇒ no sales; last-writer-wins parked tables. Details: GAPS_AND_OPEN_QUESTIONS.md §2, §7.

## E–F. Questions and discussion order

See GAPS_AND_OPEN_QUESTIONS.md §5–§6. Recommended order: data-authority policy → Plan B offline licensing → backup/restore → server availability & LAN security → secrets/PIN/permissions → plan switching & device lifecycle → outbox tooling → inventory scope → UX/localisation & diagnostics.

**Next: roadmap.** The decisions taken on these findings are in [`../adr/README.md`](../adr/README.md) (ADR-001…010) and the sequenced plan (P0 fixes, Phases 1–8) in [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).

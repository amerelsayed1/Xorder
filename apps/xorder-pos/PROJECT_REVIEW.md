# XOrder POS — Project Review

**Review date:** 2026-08-28  
**Reviewed state:** Current working tree on `main` (`f29ce42` plus uncommitted changes)  
**Scope:** Flutter/Dart application, tests, desktop deployment, database access, licensing, documentation, and release readiness

## Executive summary

XOrder POS has a strong engineering foundation and is in good prototype / internal-pilot condition. The domain model is separated from infrastructure, money uses integer minor units, database writes are transactional, secrets are kept out of the terminal JSON configuration, permissions are enforced below the UI, and the local automated suite is healthy.

It is **not production-ready yet**. The main blockers are product-completeness and operational safeguards rather than static code quality: outbound synchronization is not implemented, several revenue-critical workflows remain unfinished, the app still embeds a development licence verification key, database-backed and end-to-end tests silently skip without external setup, and there is no repository CI configuration.

### Current assessment

| Area | Assessment | Notes |
|---|---|---|
| Code quality | Good | `flutter analyze` is clean; layering and naming are generally clear. |
| Automated tests | Good locally | 213 passed, 6 skipped; meaningful domain, widget, repository, and tool coverage. |
| Architecture | Good | Domain/repository separation makes the future PostgreSQL-to-API transition feasible. |
| Security | Promising, incomplete | Secure credential storage, PBKDF2 PIN hashing, TLS policy, restricted DB grants, and signed licences are present. Release-key and operational work remains. |
| Offline/cloud behavior | Incomplete | Durable outbox/schema groundwork exists, but queue draining and platform contracts are not built. |
| Release operations | Weak | No CI workflow, no automated release gate, and environment-dependent suites are skipped by default. |
| Production readiness | Blocked | Core workflows and deployment validation still need completion. |

## What is working well

### 1. Clear architectural boundaries

The project separates `core`, `domain`, `data`, `app`, and feature presentation concerns. UI code depends on repository contracts rather than PostgreSQL directly. This is especially important because the current direct-database topology is explicitly temporary while backend contracts remain proposed.

### 2. Financial correctness receives appropriate attention

Money is represented in integer minor units, rounding behavior is isolated and tested, and order/payment writes use transactions. These are the right defaults for a POS system and reduce a large class of reconciliation defects.

### 3. Security controls are concrete

- Cashier PINs use salted PBKDF2-HMAC-SHA256 with 120,000 iterations and constant-time verification.
- PostgreSQL credentials are stored through the OS credential store rather than `config.json`.
- PostgreSQL uses `verifyFull` TLS except for loopback or explicitly trusted private-network configurations.
- Licence files use Ed25519 signatures.
- Till and management database privileges are separated, and audit records are append-only by interface, grants, and database trigger.
- Sensitive licence artifacts and generated licence files are excluded by `.gitignore`.

### 4. Test design is thoughtful

The suite covers arithmetic, authorization, licensing, setup persistence, routing/gates, PostgreSQL repositories, migrations, printing bytes, shifts, and sale flows. The end-to-end documentation also clearly explains why a real desktop device and PostgreSQL instance are required.

### 5. Documentation captures intent

The repository contains unusually detailed requirements, data contracts, deployment reasoning, licensing rules, and architecture notes. The comments around failure behavior and operational trade-offs are useful to future maintainers.

## Findings and recommended actions

### P0 — Production blockers

#### 1. Cloud/offline synchronization is not implemented

`pubspec.yaml`, `README.md`, and the integration-test documentation acknowledge that the local outbound queue is unfinished and has no platform wire contract. Yet the product documentation describes every deployment as offline-first and presents automatic/manual sync policies.

**Risk:** A cloud-mode terminal can appear configurable without having the behavior required to durably deliver sales upstream. This is a financial-data and operational-continuity gap.

**Recommendation:** Either implement and validate the outbox worker, retry/backoff, idempotency, conflict handling, observability, and cash-up drain behavior, or disable cloud mode in release builds until those capabilities exist.

#### 2. Revenue-critical workflows remain incomplete

The README lists refunds, discounts/price override, open tickets, catalogue administration, USB printer/scanner support, and some responsive shells as unbuilt. The backend order/idempotency contracts are also described as not ready.

**Risk:** The app cannot yet support the full daily and exception workflow of a production restaurant.

**Recommendation:** Define the minimum production scope explicitly. At minimum, close the order-authority/idempotency path and validate payment, receipt, void/refund, shift recovery, printer failure, and restart-after-write behavior end to end.

#### 3. The embedded licence key is explicitly a development key

`lib/features/licensing/data/license_keys.dart` warns that the current key must not ship in a release build.

**Risk:** Production licensing would rely on development key material and would have no proven rotation/release-channel procedure.

**Recommendation:** Add a build-time release-key mechanism, reject the development key in release builds, document rotation, and exercise old/new key overlap before packaging a customer build.

### P1 — High priority before a pilot

#### 4. Environment-dependent tests skip while the suite stays green

Six PostgreSQL-backed tests skip when `POS_PG_HOST` is absent, and the assembled desktop flow also requires a real device. The default `flutter test` result is therefore green without proving the actual database wiring or install-to-sale path.

**Risk:** A regression in the production data path can merge despite a green local suite.

**Recommendation:** Run PostgreSQL in CI, make the integration-tag suite mandatory there, and add a scheduled or release-gated macOS/Windows end-to-end run. Keep local self-skip behavior for developer convenience, but fail CI if an expected integration suite skips.

#### 5. No CI configuration is present

No `.github/workflows` or equivalent repository CI definition was found.

**Risk:** Analysis, tests, formatting, migrations, and packaging depend on individual developer discipline.

**Recommendation:** Add CI gates for formatting, `flutter analyze`, unit/widget tests, PostgreSQL integration tests, migration CLI tests, secret scanning, dependency review, and at least one desktop build artifact.

#### 6. Documentation has deployment-model drift

`README.md` still documents three modes—Cloud, Branch server, and Islanded—while `DeploymentMode` and `docs/pos/08-deployment-modes.md` use the newer two-mode model: Cloud and Offline, with local-versus-LAN database placement treated as configuration.

**Risk:** Installers and developers can make incompatible assumptions about what a signed licence permits and how the setup wizard should behave.

**Recommendation:** Update the README and any remaining references to the retired three-mode terminology. Add a short compatibility note for legacy `branch_server` and `standalone` wire values.

#### 7. Release validation is desktop-centric but platform declarations are broader

The product description targets Windows and macOS, while Flutter platform folders also exist for Android, iOS, Linux, and web. Android's INTERNET permission is present only in debug/profile manifests, and the README says tablet/handheld shells are unfinished.

**Risk:** Someone may produce an apparently supported build for a platform whose network permissions, UI, secure storage behavior, or tests were never release-validated.

**Recommendation:** Declare supported platforms in one authoritative place. Disable or clearly mark unsupported build targets, or add platform-specific release checks before claiming support.

### P2 — Maintainability and operational improvements

#### 8. Several source files are becoming large

Notable hotspots include:

- `lib/core/l10n/app_strings.dart` — about 2,081 lines
- `lib/features/setup/presentation/setup_panes.dart` — about 1,269 lines
- `lib/app/providers.dart` — about 717 lines
- `lib/data/postgres/postgres_admin_repositories.dart` — about 711 lines
- `lib/data/postgres/migrations.dart` — about 653 lines

**Risk:** Review cost and merge-conflict frequency will increase as setup, localization, and administration continue to grow.

**Recommendation:** Split by feature or responsibility: generated/segmented localization resources, one setup pane per file, provider groups by bounded context, and migrations grouped by version while preserving a single ordered registry.

#### 9. Error observability is limited

Several UI and setup flows translate broad exceptions into operator-facing states, which is correct for the cashier experience, but the architecture document's logging direction is not yet reflected in a visible structured logging/diagnostics subsystem.

**Risk:** Support teams may receive a generic failure without enough local evidence to distinguish database, keychain, network, or data problems.

**Recommendation:** Add redacted structured logs with correlation IDs for setup, database connection, order writes, licence activation, printing, and sync. Provide an operator-safe diagnostics export and ensure credentials/PINs/licence keys never enter logs.

#### 10. Test coverage is not measured as a release signal

The test suite is substantial, but no coverage threshold or report is configured.

**Risk:** Critical paths may lose coverage gradually without detection.

**Recommendation:** Generate coverage in CI and initially track trends rather than enforcing an arbitrary global percentage. Add targeted thresholds for money, ticket state transitions, authorization, licensing, and repository transaction behavior.

## Suggested delivery sequence

1. Freeze and document the supported production topology and platform list.
2. Make the real PostgreSQL suites mandatory in CI.
3. Complete or disable cloud sync, then prove idempotent recovery after network/process failure.
4. Replace the development licence key and test rotation.
5. Complete the minimum revenue and exception workflows for the intended pilot.
6. Add structured diagnostics, backup/restore rehearsal, and packaging/signing checks.
7. Run a controlled pilot with failure drills: database unavailable, wrong certificate, expired licence, printer offline, app restart during payment, and power loss after order submission.

## Verification performed

| Check | Result |
|---|---|
| `flutter analyze` | Passed — no issues found |
| `flutter test` | Passed — 213 tests passed, 6 skipped |
| Source inventory | 72 Dart files under `lib`, approximately 19,426 lines |
| Test inventory | 25 `*_test.dart` files under `test` and `integration_test` |
| CI configuration search | None found |
| Working-tree safety | Existing modified/untracked files were left unchanged |

## Readiness decision

**Decision: suitable for continued development and an engineer-supervised internal demonstration; not ready for an unattended production pilot.**

The fastest route to a credible pilot is not a broad UI expansion. It is to lock the deployment promise, make the real data path mandatory in CI, finish or disable sync, replace release key material, and prove the core money path under failure and restart conditions.

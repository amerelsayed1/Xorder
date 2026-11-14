# Technical plan — waiter-app

Status: **plan, not approved** · 2026-11-06 · Spec: `FEATURE.md` (W1–W9) · Verified against: xorder-pos `c67c754` (+ 8 unrelated uncommitted files: admin panes, `pos_widgets.dart`, history, installer — none on this plan's paths), xorder-cloud `775bf0f` · Related: `pos-incoming-cloud-orders` (table requests), XORD-044

## 0. What the code says (corrects FEATURE.md section 5)

| # | Finding | Evidence |
|---|---|---|
| T1 | **One POS app with two modes today**, `cloud` and `offline`, both on PostgreSQL; shared vs per-till database is `databaseHost`, permitted by the licence's `max_terminals` | `lib/core/config/deployment.dart:12-29`; `setup_controller.dart:1488` |
| T2 | Devices are `main` (holds the database) or `child`; **Android/iOS are always `child`** | `deployment.dart:125-133`; `lib/app/providers.dart:2145` |
| T3 | **No branch-server process or local API exists**; tills talk straight to PostgreSQL as `pos_till`; a local HTTP service for tablets is only a doc recommendation | `deployment.dart:156-160`; `docs/pos/08-postgres-lan.md:109-120` (POS repo) |
| T4 | On Android/iOS the database password would be stored in a **plain file** (`DevelopmentFileSecretStore`) | `lib/data/.../secret_store.dart:59-87` |
| T5 | **XORD-044:** a seated ticket's save replaces the table's check with no version or lock; each till loads the floor once at start | `postgres_parked_tickets.dart:85-105`; `providers.dart:952-1006`; `floor_overlay.dart:5-9` |
| T6 | A round exists on lines (`roundNumber`, `sendRound`) but records **no time and no staff**, is kept in memory until the ticket is parked, and **prints no kitchen docket**; the print queue knows only `receipt`/`reprint`; one printer per till | `ticket.dart:49,186,621`; `ticket_engine.dart:494-509`; `providers.dart:1644`; `sale_screen.dart:522-533`; `postgres_print_queue_repository.dart:51`; `providers.dart:826-850` |
| T7 | Roles seeded: owner, manager, supervisor, cashier — **no waiter**; `pos_shifts` is a cash shift; **no clock-in**; tickets have **no "opened by"** (settled orders have `served_by`, line events `staff_id`) | `permissions.dart:653-700`; `migrations.dart:281-324,826`; `postgres_orders_repository.dart:107-109` |
| T8 | Android id `com.example.xorder_pos`, debug signing; iOS `com.example.xorderPos`, iOS 15; sale screen has 1100/700 px breakpoints, **floor screen has none** | `android/app/build.gradle.kts:8,19-23,36`; `ios/Runner.xcodeproj/project.pbxproj:363,387`; `sale_screen.dart:627,700-733`; `floor_screen.dart` |
| T9 | **No device-type field** on cloud or POS terminals; cloud licences do not count terminals; offline licences count at activation | `PosTerminal.php:40-44`; `migrations.dart:152-165`; `LicenceActivator.php:88-120`; `.claude/rules/licences.md` |
| T10 | Invoice numbers are already safe across tills (`FOR UPDATE` per branch and year); settlement idempotent on `client_transaction_id` | `postgres_orders_repository.dart:38,119,401-445` |
| T11 | **No store on the device itself**; the outbox is in the branch database and drains only on a main device | `migrations.dart:345,4358`; `outbox_drain.dart:336-348`; `providers.dart:675` |
| T12 | In **offline** mode there is no cloud, so table-QR requests (bill / call waiter) **cannot exist** there; they come only in cloud mode via `pos-incoming-cloud-orders` | T1 + companion feature |

## 1. New owner decisions (2026-11-06)

- **W10 Two separate POS apps with shared modules**: a cloud app and an offline app, built from shared packages. This is a restructuring of the POS repository and gets **its own feature description** (`/develop-feature pos-two-apps`); this plan only places the waiter code in modules both apps can share and does not split the repo.
- **W11 The waiter app works with both** the cloud and the offline POS.
- **W12 XORD-044 is fixed first**, as stage WS1, because it protects today's multi-till restaurants as well.

## 2. Decision this plan needs: how handhelds connect (Q3)

*Recommended:* **a small branch service on the main device** (Dart `shelf`, running inside the main POS app), reusing the existing `postgres_*` repositories. Handhelds talk only to it, with a per-device token over the LAN with TLS (`lan_tls.dart` exists); changes are pushed to handhelds by server-sent events fed by PostgreSQL `NOTIFY`.
- Why: no database password on phones (T4); one place for the check lock (BR-1), idempotent late rounds (W6) and pricing (BR-2); a database migration does not force every phone to upgrade at once; a lost phone is revoked by its token.
- *Alternative:* handhelds connect straight to PostgreSQL like child tills — less code, but needs an OS keystore on mobile, gives each phone wide database rights, and every rule lives in each client.
- Desktop child tills stay on direct SQL for now; they get the same lock (WS1).

## 3. Reuse

`TicketEngine` (lines, rounds, voids with approver, refusals as data) · `ParkedTicketCodec` · `postgres_*` repositories · invoice sequence lock (T10) · PIN sign-in and permission resolver · `lan_tls.dart`/`pos_tls.dart` · ESC/POS printing (`receipt_printing.dart:159-187`) for dockets · sale screen narrow layouts (T8) · `pos-incoming-cloud-orders` feed + FCM nudge for table requests (cloud mode).

## 4. Stages

All POS migrations additive, applied by `bin/pos_migrate.dart`, tested on throwaway PostgreSQL databases dropped after the run (`scripts/check.sh`).

| Stage | Paths | Change | Tests | Rollback |
|---|---|---|---|---|
| **WS1 Check lock and live floor (XORD-044)** | `lib/data/postgres/migrations.dart` (new: `pos_parked_tickets.version int not null default 0`), `postgres_parked_tickets.dart`, `providers.dart`, floor/sale providers | save = compare-and-swap on `version` (`UPDATE … WHERE version = @expected`; insert only if the table is free); a stale save returns a `TicketRefusal` "changed on another till" and reloads; main device emits `NOTIFY pos_floor` on save; tills refresh the floor on notify (child tills: poll every 5 s as a fallback) | PG suite: two connections, stale save refused, first check intact (XORD-044 box 1); floor refresh after a save from another connection (box 2); `parked_tickets_schema_test`, `open_tickets_test`, `floor_overlay_test` stay green | column unused; revert code |
| **WS2 Rounds as records** | `ticket.dart`, `ticket_engine.dart`, codec, migrations (`pos_ticket_rounds`: ticket txn, round no, sent_at, sent_by, device_id, client_round_id unique), sale screen send | sending a round saves the ticket and a round row in one transaction; ticket gets `opened_by`; `client_round_id` makes a resent round a no-op | engine unit tests (time/staff on round, idempotent resend); PG test for one transaction; `ticket_engine_test` regression | revert; table unused |
| **WS3 Kitchen dockets** | print queue kind `kitchen`, printer config per station/category, `receipt_printing.dart` docket layout (ar/en) | each sent round queues a docket per kitchen printer; void-after-send queues a void docket | unit tests for docket content and routing; print queue PG test; **paper checked by a person** | disable kitchen printers |
| **WS4 Branch service** | new `lib/server/` (shelf), started by the main device; per-device token table (`pos_devices`: id, kind, token hash, revoked_at) | endpoints: sign-in by PIN, catalog, floor, check get/save (versioned), send round (by `client_round_id`), print bill (to the cashier's printer, W8), clock-in/out; SSE stream from `NOTIFY` | `flutter test` with an in-process server: auth/revoked token 401, stale save 409, round resend once, cross-branch refusal | service off by default |
| **WS5 Waiter role and clock-in** | `permissions.dart` (waiter preset: `pos.operate`, item cancel before send; no payment, no refunds, no cash), migrations (`pos_clock_events`: user, device, in/out, at), clock-in UI, per-waiter figures (Q11) | a waiter cannot open a table before clocking in (AC-11); every line/round carries the waiter (BR-5, BR-9) | permission resolver tests; PG test for clock events; widget test for the gate | role unused |
| **WS6 Device kind and licence limit** | POS `pos_terminals`/`pos_devices.kind` (`till`/`waiter`); cloud `pos_terminals.kind` (additive), licence field `max_waiter_devices` through the **renewal path** (`LicenceIssuer`, `RenewLicenceRequest`, `LicenceDetails.vue`; `.claude/rules/licences.md`), plan field | registering a waiter device beyond the limit → refused with its own message in both languages (AC-13); offline licences count at activation like tills; cloud: counted on registration (new behavior — cloud tills stay uncounted) | cloud: `LicenceRenewalUpgradeTest` extended; activation seat test for waiter kind; POS: `licence_seats_full_test` pattern for the new refusal | field ignored if absent |
| **WS7 Handheld app** | Android/iOS app ids and release signing, OS keystore for the device token (Keystore/Keychain), phone and tablet layouts for floor, menu, check, requests (`lib/features/waiter/` in a module both future apps share, W10), device-local queue for rounds (W6) | waiter flow end to end; queued rounds shown "queued, not in the kitchen yet", sent once on reconnect, refused rounds shown as failed (AC-10) | widget tests at phone (390×844) and tablet (800×1280) sizes, en/ar; queue unit tests with a fake service; **real Android and iOS devices checked by a person** | do not distribute builds |
| **WS8 Table requests on handhelds (cloud mode only)** | consume `pos-incoming-cloud-orders` S4 feed on the main device, forward over SSE; FCM nudge to handhelds | request shows on the check's waiter first, then all (W5); clearing on any device clears everywhere (AC-6) | in-process server test; depends on POS-BE-033 READY | hidden in offline mode (T12) |
| **WS9 Docs** | workspace `docs/features/waiter-app/{API,DATABASE,TEST_PLAN,TEST_REPORT,CHANGELOG}.md`; POS repo `docs/pos/08-postgres-lan.md` (branch service), stale `08-deployment-modes.md:213-224` | — | `bash scripts/harness/verify.sh` | — |

Order: WS1 → WS2 → WS3 (useful for today's tills too) → WS4 → WS5 → WS6 → WS7 → WS8. WS1–WS3 ship in a normal desktop POS release before any handheld exists.

## 5. Rollout

1. Desktop POS release with WS1–WS3 (fixes XORD-044, kitchen dockets).
2. Cloud release with WS6 cloud fields (additive; nothing enforced until a waiter device registers).
3. Desktop POS release with WS4–WS6 (branch service off by default).
4. Handheld builds to a pilot restaurant (Android first, then iOS through TestFlight or MDM).
5. Per branch: waiters live → then switch on table-ordering retirement in `pos-incoming-cloud-orders` (D9).

Old handheld vs newer main device: the service keeps old fields (additive API, version reported by each device); a main device older than the handheld → handheld says "update the main POS" and does nothing.

## 6. Domain lens

Restaurant: the target (open checks, rounds, kitchen, bill at the end). Café with table service: same. Food truck and cloud kitchen: no tables — unaffected, but WS1–WS3 (lock, rounds, dockets) still help any multi-till or kitchen-printing site. No dependency on tips, KDS, aggregators, recipes, loyalty or multi-brand; card payment at the table stays out (W4).

## 7. Verification commands

- POS: `cd apps/xorder-pos && flutter analyze && flutter test`, then `scripts/check.sh` (PostgreSQL suites; needs `POS_PG_*`, databases dropped after the run; reported as not run otherwise).
- Cloud (WS6): `cd apps/xorder-cloud/apps/api && php artisan test --filter 'Licence|PosTerminal'`, then the full suite; `pnpm --filter @xorder/web build` for the licence form.
- Builds: `flutter build apk` / `flutter build ipa` (signing keys are the owner's; not done by Claude).
- Harness: `bash scripts/harness/verify.sh`.

## 8. Risks

- WS1 changes how every multi-till site saves tables; a stale-save refusal is new behavior cashiers will see.
- A server process inside the main POS (WS4): if the main device sleeps or closes, handhelds stop; the main device must stay on during service.
- Restaurant Wi-Fi quality; Android device variety; Apple distribution needs an Apple developer account (owner).
- W10 (two apps) may move files this plan touches; plan WS7 code into shared modules so the split does not redo it.
- SQLite is not involved; PostgreSQL locking is tested on real throwaway PostgreSQL in `scripts/check.sh`, not on the cloud SQLite suite.

## 9. Approvals needed before building

1. The connection design in section 2 (branch service on the main device) — or direct PostgreSQL.
2. Starting with WS1 (XORD-044) now, as its own small change, before the rest is approved.
3. Additive POS migrations (WS1, WS2, WS4, WS5, WS6) and cloud migrations (WS6).
4. Licence change: a new `max_waiter_devices` through the renewal path, and counting waiter devices for cloud licences (cloud tills stay uncounted).
5. New dependencies: `shelf` (WS4), an OS secure-storage plugin (WS7), `firebase_messaging` (shared with the other feature).
6. Release signing and store/MDM accounts for Android and iOS (owner's accounts; Claude never handles the keys).
7. Nothing is committed or pushed.

Open (not blocking WS1–WS3): Q10 seats and price per plan, Q11 per-waiter figures, Q12 late-round marking, W10's own description.

## 10. As built — WS1 (2026-11-06, uncommitted, xorder-pos `c67c754` + working tree)

- Migration 63: `pos_parked_tickets.version integer NOT NULL DEFAULT 0`, moved on by the save (`version = version + 1`). No trigger and no older-till compatibility: no restaurant runs the current POS, so this is treated as the first version (owner, 2026-11-06).
- `PostgresParkedTickets.save(ticket, expectedVersion:)`: free table → `INSERT … ON CONFLICT DO NOTHING RETURNING version`; known version → `UPDATE … SET version = version + 1 … WHERE version = @expected RETURNING version`; no row → `ParkedTicketChanged`. Held tickets unchanged (XORD-046). `remove` matches the table only at the expected version. `refresh()` is the throwing read, `load()` the safe one; both return `ParkedFloor` with versions.
- `OpenTicketsController.park` returns `ParkOutcome` (`parked`, `failed`, `changedElsewhere`); a refusal starts a refresh and keeps the live ticket. `refresh()` every 5 s when the till has a database; a read overlapping a local write is discarded.
- **Deviation from the plan:** no `NOTIFY pos_floor`; a 5 s poll on every till. The guarded save, not the refresh, prevents the overwrite.
- Tests and results: `docs/qa/XORDER_QA_FINDINGS.md` XORD-044.
- XORD-045 (paying an outdated copy), added 2026-11-06: `submit(tableVersion:)`; the parked row is locked, checked and deleted inside the order's transaction (`PostgresOrdersRepository._takeParkedCheck`). The payment screen no longer relies on `settle` to clear the parked row; `settle` still runs and only updates the till's memory.
- XORD-046 (held tickets), added 2026-11-06: the same compare-and-swap for a held row, keyed by transaction id; versions kept per held ticket in the till; paying a held ticket uses the same guard. `submit`'s parameter is now `parkedVersion`.
- Still open: voiding an outdated copy is not version-checked (see XORD-046 in section 8).


## 11. As built — WA1, the first handheld slice (2026-11-09, uncommitted, xorder-pos `development` on `6a5ceda`)

Built overnight on the owner's instruction "start working on waiter app, don't ask me anything, make it in same monorepo" (2026-11-09). The decisions below were taken without asking, following this plan's recommendations; each is listed so it can be reversed.

### Decisions taken (owner to confirm)
| # | Decision | Why | Reversible by |
|---|---|---|---|
| D-WA1 | **Q3: handhelds talk to a link server inside the till that holds the tables**, never to the database | §2's recommendation: no database password on a phone (T4), one place for the version check and pricing | — (the alternative, direct SQL, was rejected in §2) |
| D-WA2 | **Thin handheld**: it sends *operations* (add item with options, change quantity, note, remove unsent line, guests, send round); the till applies them with its own `TicketEngine` and returns the priced check | BR-2: nothing priced on the phone; the phone needs no tax config, no engine, no catalog codec | — |
| D-WA3 | **`dart:io` HttpServer/HttpClient, no `shelf`** | §9.5 asked approval for new dependencies; none were added | swap in `shelf` later behind the same handler |
| D-WA4 | **Same monorepo**: new members `packages/xorder_waiter_link` (pure Dart: wire, client, server) and `apps/xorder_pos_waiter` (Flutter: Android, iOS). The handheld depends on the link package only, never on `shared_module` | the phone must not ship PostgreSQL, the encrypted SQLite engine or desktop screens (owner: "no unused code") | — |
| D-WA5 | Host = **offline main device, or a cloud till** (each cloud till keeps its own tables since pos-cloud-single-till-sqlite); child tills do not serve | W11 (both apps); one pairing point per floor | `WaiterLinkHost._canHost` |
| D-WA6 | **Off by default**, turned on per till (`waiter.link_enabled`, terminal scope) from Settings › Waiter devices, gated on `terminal.manage`; then starts at every launch | a till must not open a port nobody asked for | the setting |
| D-WA7 | Port **8787**, plain **HTTP on the LAN** | first slice | TLS is the first follow-up (below) |
| D-WA8 | Pairing: **6-digit code, 10 minutes, one use**; device token 32 random bytes, **only its SHA-256 stored** (migration 65); revoke stamps `revoked_at`, row kept | T4/§2; a copy of the table or a backup opens nothing | — |
| D-WA9 | Waiter session = **the till's own PIN check** (`SessionRepository.signIn`, read-only), requires `pos.operate`; 5 wrong PINs or codes → 1-minute lockout; session ends after 12 h idle | same people, same PINs as the lock screen | constants in `WaiterLinkServer` |
| D-WA10 | Removing an unsent line (and quantity to 0) = `TicketEngine.cancelLine`, needs `order.item.delete_before_send`, recorded as `removedBeforeSend` with the waiter's id — the till's own rule (`line_void_dialog.dart`) | BR-3, BR-5 | — |
| D-WA11 | **Refused on a handheld in WA1** (the till does them): voiding a sent line, discounts, price overrides, payment (W4), open-price items, combos, and any edit once the cashier has started taking payment (`payment_started`) | keeps WA1 small and money-safe | — |
| D-WA12 | Floor refresh on the handheld every **5 s** (the tills' own cadence, XORD-044); after a handheld save the serving till refreshes its floor at once | no push channel yet | SSE later |
| D-WA13 | Handheld default language **Arabic**, one-tap switch on every screen | Egypt first | `WaiterAppState.locale` |
| D-WA14 | Pairing (address + token) kept in a **file in the app's private support folder**, not the OS keystore | no new plugin (§9.5) | Keystore/Keychain plugin — follow-up |

### What exists
- `packages/xorder_waiter_link/`: `wire.dart` (menu, floor, check, ops, error codes, money as minor units + exponent, wire version 1), `server.dart` (`WaiterLinkServer`: routes `/v1/hello`, `/v1/pair`, `/v1/sign-in`, `/v1/sign-out`, `/v1/menu`, `/v1/floor`, `/v1/tables/{id}/check`, `/v1/tables/{id}/ops`; pairing, device auth, sessions, lockouts; `WaiterLinkBackend` interface), `client.dart` (`WaiterLinkClient`).
- `packages/shared_module/`:
  - `lib/features/waiter_link/till_waiter_backend.dart` — `TillWaiterBackend` (the till's answers, `TicketEngine` ops, version-checked save via `PostgresParkedTickets`, all-or-none).
  - `lib/features/waiter_link/waiter_link_host.dart` — `WaiterLinkHost` / `waiterLinkHostProvider` (start/stop, pairing code, devices, revoke; watched from `app.dart` like the cloud sync loop); `waiterLinkPortProvider`.
  - `lib/features/waiter_link/waiter_devices_dialog.dart` — Settings › Waiter devices.
  - `lib/data/postgres/postgres_waiter_devices.dart` — `pos_waiter_devices` on either engine.
  - Migration 65 (`migrations.dart`) + `sqliteUpgrades[65]`; till grant in `local_bootstrap.dart`; `SettingKey.waiterLinkEnabled`; 18 strings in `app_strings.dart` (en/ar); menu entry in `app.dart`.
- `apps/xorder_pos_waiter/`: `main.dart`, `state.dart` (pairing store, client factory, phases), `strings.dart` (en/ar, every till code worded), `theme.dart` (the till's light palette, radius 0, no shadows), `screens/` (connect, PIN, floor, check with menu/options/line sheets; tablet ≥ 700 px shows menu and check side by side, phone uses tabs). Android: INTERNET + cleartext for the LAN; iOS: local-network usage text + `NSAllowsLocalNetworking`. App ids are Flutter's defaults under `io.xorder` (signing is the owner's).
- `scripts/check.sh` runs both new members and the device suite on SQLite.

### Not done in WA1 (next, in order)
1. **TLS on the link** (`lan_tls.dart` has the certificate-pinning pieces) — the PIN and token cross the LAN in clear today. **Do not pilot in a restaurant before this.**
2. Device token in Keystore/Keychain (needs `flutter_secure_storage` or similar — approval).
3. WS2 rounds as records (time, waiter, device on each round) and WS3 kitchen dockets — a round sent from a handheld today marks lines sent exactly as the till's own send does, and prints nothing (same as the till, T6).
4. W6 offline queue on the handheld (today a send without Wi-Fi fails with "cannot reach the till"; nothing is queued).
5. WS5 waiter role preset and clock-in (W9); per-waiter figures (Q11).
6. WS6 waiter-device licence limit (W7, Q10) — today any number of devices can pair.
7. WS8 table requests on the handheld (cloud mode).
8. Push (SSE) instead of the 5 s poll; "print bill at the cashier's printer" (W8).
9. Real-device checks on Android and iOS phones and tablets, by a person (AC-9).


## 12. Plan — POS-BE-033, the cloud half of the waiter wire (2026-11-09, **not approved, nothing built**)

Spec: `apps/xorder-pos/docs/coordination/POS_TO_BACKEND.md` POS-BE-033 (PROPOSED) · client: `packages/xorder_waiter_link` (`wire.dart`, `client.dart`) · Verified against: xorder-cloud `775bf0f` with **45 uncommitted files** in the tree (none on the paths below except `routes/api.php`, which is not among them; `Enums/Feature.php`, `PublicOrderController.php`, `OrderResource.php` are dirty and this plan does not edit them).

### 12.1 What the code says
| # | Finding | Evidence |
|---|---|---|
| C-1 | No waiter route exists; the closest are the till's device-token routes (`pos.device`, tenant pinned by `TenantContext::overrideId`) and the public slug routes (`public/restaurants/{slug}/…`) | `routes/api.php:823-830, 870-892`; `Middleware/PosDeviceAuth.php` |
| C-2 | **Tenant from the host (`{slug}.xorder.io/api/pos/waiter`) is UNVERIFIED.** Existing public routes carry the slug in the path; `config/platform.php` mentions per-restaurant subdomains only for the menu (`tryorder.net`, wildcard DNS/TLS). Whether `{slug}.xorder.io` serves `/api` is a deploy/DNS fact I could not confirm | `config/platform.php:17-18`; client `apps/xorder_pos_waiter/lib/state.dart:138` |
| C-3 | Server-side pricing already exists for the till: `PosPricingEngine::price()` (unit price from menu + option deltas, charges, tax). The QR path still trusts `line_total` | `Services/PosPricingEngine.php:48`; `PublicOrderController.php:80-93` |
| C-4 | A visit/round model exists: `table_visits` (open/closed), `order_rounds` (sequence, submitted_at), `order_items.order_round_id` NOT NULL. **A draft line has no home** (needs one) and neither visits nor orders have a `version` | migration `2026_08_19_000100_create_table_visits_and_order_rounds.php`; `Models/TableVisit.php` |
| C-5 | POS PIN is stored (salt, hash) on `users` (PBKDF2-SHA256, 120000 it.) but there is **no verify helper** (only `make`/`wire`); `users.username` exists | `Support/PosPin.php`; migration `…add_username_to_users_table.php` |
| C-6 | `pos.operate` is an existing tenant capability, the one the sign-in must require | `Enums/TenantCapability.php:93` |
| C-7 | The contract's own rule: restaurants **with** the `pos` feature use the offline flavor; the cloud flavor is for restaurants **without** a till. So the waiter routes must **not** sit under `feature:pos`; they need `table_management` (+ `system_ordering` for orders) | POS-BE-033 "Rule that decides which flavor…"; `Enums/Feature.php` |

### 12.2 Acceptance criteria (proposed; the contract table is the source)
- **AC-C1** `GET hello` answers `{wire:1, name}` unauthenticated for an existing slug; unknown slug → `NOT_FOUND`, same shape.
- **AC-C2** Sign-in by staff `username` + POS PIN requires `pos.operate`; one error for either wrong; 5 failures per device (per IP when no device) → `TOO_MANY_ATTEMPTS` for 1 minute. A first sign-in returns `device_token` once (stored hashed); a later one with the token does not.
- **AC-C3** Every call after sign-in needs `Authorization: Device` **and** `X-Waiter-Session`; session idles out at 12 h; a revoked device → `DEVICE_REVOKED`.
- **AC-C4** **Tenant boundary:** a device or session of restaurant A can never read or write restaurant B's menu, floor or check, by slug or id.
- **AC-C5** `menu` and `floor` return the wire shapes; `floor` state is `free | open | bill_asked` from the open visit and open bill request.
- **AC-C6** `ops` are applied all-or-none; every price, modifier delta, subtotal, service, tax and total is computed on the server and **no price is read from the request**; stale `version` → `409 CHECK_CHANGED` with the current check.
- **AC-C7** `send` turns the draft lines into one round (order + `order_rounds` + `order_items`) in one transaction; repeating the same request after success is refused as `CHECK_CHANGED` (the version moved), never a second round.
- **AC-C8** Draft lines are shared by every device at the table (one unsent round per visit).
- **AC-C9** The dashboard can list and revoke waiter devices.

### 12.3 Stages (backend contract first; additive schema first)
| Stage | Paths (xorder-cloud/apps/api) | Change | Tests | Rollback |
|---|---|---|---|---|
| **C1 Schema + models** | new migrations; `Models/PosWaiterDevice`, `PosWaiterSession`, `TableCheckDraft`; `Support/PosPin::verify` | `pos_waiter_devices` (restaurant_id, name, token_hash unique, last_seen_at, revoked_at, created_by); `pos_waiter_sessions` (token_hash, device_id, user_id, last_seen_at, expires_at); `table_check_drafts` (table_visit_id, lines json, guests); `table_visits.check_version int default 0`. **All additive, nothing dropped or backfilled** | model/unit: `PosPin::verify` (right, wrong, null hash) | drop the new tables/column (empty until used) |
| **C2 Routing, auth, sign-in** | `routes/api.php` (new `pos/waiter/v1` group), `Middleware/WaiterDeviceAuth`, `WaiterSessionAuth`, `Http/Controllers/PosWaiter/AuthController`, wire error envelope | tenant resolved from the **slug** (host or path: see Q1), pinned with `TenantContext::overrideId` and released in `finally`; hello, sign-in, sign-out; throttles | Feature: AC-C1…C4, lockout, revoked, wrong feature, two tenants | remove the route group |
| **C3 Reads** | `PosWaiter/MenuController`, `FloorController`, `CheckController`; a mapper service reusing `PublicMenuService` | menu (no combos/open price), floor, check | Feature: AC-C5, tenant boundary, shapes against `wire.dart` fixtures | remove routes |
| **C4 Ops + send** | `Services/WaiterCheckService` (draft ops, CAS on `check_version`, pricing through `PosPricingEngine`, `send` → order/round/items in `DB::transaction` with the visit row locked) | AC-C6…C8; kitchen notification as the QR order does (Q4) | Feature: all-or-none, stale version 409, client price ignored, double send, two devices, concurrency (two simultaneous ops, one wins) | remove routes; rounds already sent stay as ordinary orders |
| **C5 Dashboard devices** | `Dashboard/PosWaiterDeviceController`, routes under `can:pos.provision`-equivalent (Q5), Vue list/revoke in `apps/web` | AC-C9 | Feature for the API; `pnpm build` for Vue (no JS test framework: manual steps listed) | remove routes/page |
| **C6 Docs** | `docs/features/waiter-app/{API,DATABASE,TEST_PLAN,TEST_REPORT,CHANGELOG}.md`; POS-BE-033 → APPROVED/READY in both `docs/coordination/` copies | as-built, with real revisions | `bash scripts/harness/verify.sh` | — |

Order: C1 → C2 → C3 → C4 → C5 → C6. Cloud ships first; the handheld already speaks this wire, so nothing on the POS side changes (a failed sign-in is today's behaviour).

### 12.4 Verification commands
`cd apps/xorder-cloud/apps/api && php artisan test --filter 'Waiter|PosPin'`, then the full `php artisan test`; `cd apps/xorder-cloud && pnpm --filter @xorder/web build` for C5. SQLite in-memory cannot prove PostgreSQL row locking (`lockForUpdate`) or the concurrency of the version check: the concurrency test is the closest, and the lock behaviour is reviewed by reading and **listed for a person on a PostgreSQL copy** (never production). `/release-check` before anything is pushed.

### 12.5 Domain lens
Helps: restaurants and table-service cafés without a till (open checks, rounds). Not applicable: food truck, cloud kitchen (no tables). Depends on known gaps: no kitchen steps/KDS (F1), so `send` can only notify as the QR order does; no tips; no served mark (F2).

### 12.6 Risks
- **Production:** `main` auto-deploys and runs `migrate --force`; all migrations here are additive, but nothing is pushed by Claude.
- Two writers for one table if a restaurant has both a till and cloud waiters: blocked by the flavor rule only by plan/licence, not by code (propose: refuse sign-in when the tenant has the `pos` feature, C-7).
- The QR path keeps its pricing gap; this plan does not touch it (a shared pricing service is the later fix).
- A 4-digit PIN over the internet: lockout is per device/IP, so a distributed guess is possible; rate limits and the `pos.operate` gate contain it, not eliminate it.

### 12.7 Approvals needed
1. The additive migrations in C1 (written, **not run** by me).
2. The route group and error envelope as the public contract (POS-BE-033 moves PROPOSED → APPROVED).
3. Q1 below (it decides C2).

### 12.8 Open questions
- **Q1 Host or path?** Does `{slug}.xorder.io/api/...` reach the API (wildcard DNS/TLS on xorder.io)? If not, the handheld's base URL must change to a path form, which is a one-line client change. Needs the owner (deploy fact).
- **Q2 Branch:** a visit has a `branch_id`; which branches may a waiter see (the staff user's branch, or all)? User/branch assignment is UNVERIFIED.
- **Q3 Order `source`/channel value** for waiter rounds, and whether to stamp the waiter (`order_rounds.submitted_by`, additive) for the Live board.
- **Q4 Kitchen notification** on `send`: the QR order's push, or none.
- **Q5 Permission** for listing/revoking devices (reuse `pos.provision`, or a new capability).
- **Q6 Plan limits** for waiter sessions/devices (POS-BE-033 open question; WS6 licence work is separate).


## 13. As built — POS-BE-033 cloud half (2026-11-09, uncommitted, xorder-cloud `775bf0f` + working tree)

Plan §12 with these decisions (owner chose "use path" for Q1; the rest were taken without asking and are open for reversal):
- **Q1 base URL:** slug in the path. `{slug}.xorder.io/api` was not verified and is not used. Routes `/api/pos/waiter/{slug}/v1/*`; the handheld builds `https://xorder.io/api/pos/waiter/<slug>`.
- **No pairing step:** the first sign-in registers the phone (contract text), `PosWaiterDevice`/`PosWaiterSession`, tokens `xwd_`/`xws_` hashed with the app-key HMAC (`DeviceToken::hash`).
- **One order per visit:** the check is the visit's NEW order (what the QR path already appends to) plus the shared draft; `send` appends a round, or creates the order with `source='waiter'`. Q3 default: no new `channel`; no stamp of the waiter on the round (the order's `acting_user_id` is set only when the waiter creates it).
- **Q2 branch:** a waiter sees every active table of the restaurant (no staff-to-branch restriction; UNVERIFIED that users carry one).
- **Q4:** `send` raises the same `order.created` notification a QR order does.
- **Q5:** devices list = `tables.view`, revoke = `tables.update` (no new capability).
- **Not enforced:** refusing cloud sign-in for a restaurant that has the `pos` feature (the plan's risk mitigation); it would block testing on a restaurant that has both.
- **Deviation from the plan:** the Vue page for devices (C5) was not built; only the API.
- Known limitations: the floor prices every open table on each read (one pricing run per open table); sent lines of a QR order have phone-written prices and are shown at those prices; no audit-log entry for device registration or revocation; no plan/licence limit on waiter devices (Q6).

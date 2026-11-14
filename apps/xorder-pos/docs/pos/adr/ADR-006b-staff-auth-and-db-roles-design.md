# ADR-006b — Staff username + password (Slice D) and per-till DB roles (Slice E): implementation design

**Status:** Proposed technical design. Written 2026-10-25 by reading code only. **Nothing here was run**: no
Flutter, Dart or PostgreSQL in the planning sandbox. Extends [ADR-006](ADR-006-security.md) and Phase 1 of
[`../20-implementation-roadmap.md`](../20-implementation-roadmap.md). Every statement not read from the
repository is tagged **[ASSUMED]**. Anything the product owner must choose is tagged **[OPEN]** and collected
in the last section; nothing is decided silently.

**Another agent is editing `lib/` and `installer/` while this is written.** In particular `router.dart` already
carries a `LockReason.inactivity` and `LockScreen(afterInactivity: ...)`, so an idle lock may be landing
independently. Re-read `router.dart`, `lock_screen.dart` and `lib/data/config/*` before starting; line numbers
below are from the tree as read and will drift.

---

## 0. Reading map (what the design stands on)

| Fact | Where |
|---|---|
| `pos_staff(id, restaurant_id, branch_id, name, username, pin_salt NOT NULL, pin_hash NOT NULL, capabilities text[], is_active, created_at)`, `UNIQUE (restaurant_id, username)`; later `role_id`. | `migrations.dart:171-185` and later |
| PIN = PBKDF2-HMAC-SHA256, 120 000 iterations, 16-byte salt, base64 of the 32-byte key, exactly 4 digits. `PinHash.verify` is constant-time on the client. | `pin_hash.dart` |
| Lock screen already asks **username + PIN** (`signInAs`) with name tiles; no lockout. Admin Mode and the forced terminal reset use `checkStaffPin` -> `signInAs`. Supervisor override uses **PIN only** via `staffDirectoryRepositoryProvider.byPin`. | `lock_screen.dart`, `admin_session.dart:130-165`, `supervisor_override.dart:319` |
| `signInAs` fetches every active staff row and hashes the PIN against all of them (timing flattening). | `postgres_directory_repositories.dart:425-470` |
| Admin Mode lockout: 5 failures, 30 s doubling to 15 min, **in memory, per terminal**. | `admin_session.dart:205-232` |
| `pos_till` is created `LOGIN PASSWORD` only; `pos_admin` `LOGIN CREATEDB`, no CREATEROLE; `pos_backup` `pg_read_all_data`. `createRoles` is "the installer's step" and needs superuser/CREATEROLE. | `local_bootstrap.dart:177-307` |
| One grant list `tillGrants(database, role, cloudSeeding)`; offline REVOKEs till writes on `pos_staff`, catalogue, tenders, receipt profiles, `pos_refunds` UPDATE. Cloud till may INSERT/UPDATE `pos_staff`. | `local_bootstrap.dart:655-973` |
| Till has SELECT on `pos_staff` (hashes), `pos_roles`, `pos_staff_roles`, `pos_staff_permission_overrides`, `pos_permission_limits`; INSERT on `pos_audit_events`, `pos_cash_movements`, `pos_refunds*`; UPDATE (column-scoped) on `pos_orders` status/void columns; table-wide UPDATE on `pos_shifts`, `pos_terminals`, `pos_outbox`, `pos_sync_outbox`. | `local_bootstrap.dart:663-856` |
| Management (staff, roles, settings, menu) runs on the **admin** connection, not the till role; `resetPin` etc. refuse with `AdministratorCredentialRequired` when no admin password is in hand. | `postgres_admin_repositories.dart:768-830` |
| `terminal_id` columns: `pos_orders` (uuid NOT NULL, line 51), `pos_shifts` (285), `pos_audit_events` (469, nullable), `pos_refunds` (1149), `pos_cash_drawers` (1444, nullable), `pos_cash_movements` (1503), `pos_print_jobs` (3170, **text**), `pos_backups` (3421). | `migrations.dart` |
| Existing `SECURITY DEFINER` pattern with pinned `search_path`: refund counter triggers (mig 12), one-owner trigger (mig 42). | `migrations.dart:1231-1305, 3706-3850` |
| Last migration: **53** (`pos_terminals.install_id`). | `migrations.dart:4470` |
| Child till registration today: connects with the **shared `pos_till` password** (typed/copied), verifies a manager's username + PIN against `pos_staff`, `registerManually` upserts `pos_terminals` on `(restaurant_id, install_id)`. | `postgres_directory_repositories.dart:141-300`, `setup_controller.dart:1400+` |
| Cloud: bootstrap bundle `staff[].pin {algorithm, iterations, salt, hash}`; seeder writes `pin_salt/pin_hash` with `ON CONFLICT (id) DO UPDATE`, empty strings when no PIN. POS-BE-024 fixes the PIN at **exactly 4 ASCII digits**, PBKDF2 120 000. | `bootstrap_seeder.dart:459-480`, `BACKEND_TO_POS.md:2077-2112` |
| Restore is `pg_restore --clean --if-exists --no-owner --single-transaction`; ACLs are **not** suppressed. Roles are cluster-level and are not in a single-database dump. | `pg_archive.dart:226-244` |
| `grants_cover_usage_test` greps each till-repository **source file** for every `CREATE TABLE` name and demands the name appear in `tillGrants`. A new table named in till-repository Dart must therefore be granted, or be touched only through a function. | `test/data/grants_cover_usage_test.dart` |
| `check.sh` runs tests as `$USER` (a superuser); `pg_fixture` defaults to `pos_till` only when no env is set. Superuser sessions bypass grants, so existing suites prove nothing about role enforcement; only `*_grants_enforced_test` style suites create real roles. | `scripts/check.sh`, `pg_fixture.dart:50-58` |
| Installer ships **PostgreSQL 16** (EDB); Homebrew advice is `postgresql@16`. | `18-windows-installer.md:14`, `check.sh` |

---

# SLICE D — Staff username + password per session

## D1. Principle: the DB verifies, the till never needs to read a verifier

Today the till SELECTs `pin_salt/pin_hash` for every staff row and compares in Dart, so a stolen till
credential or backup yields every hash for offline cracking. For a *password* we can avoid repeating that:

* The client derives `K = PBKDF2-HMAC-SHA256(password, salt, iterations)` (pure Dart, `cryptography`, already a dependency).
* It sends `K` (base64) to a `SECURITY DEFINER` function over the LAN (TLS is Phase 1 too). The DB compares `K` with the stored derived key. The server **never** receives the password, and the till role needs **no SELECT** on the new column.
* `K` is password-equivalent on the wire. That is acceptable only with TLS on; it is the same trade-off the existing `pos_admin` password makes. **[ASSUMED]** TLS lands in the same phase (installer owns it).
* Rejected: verifying in SQL with `crypt()`/pgcrypto bcrypt (adds an extension, breaks the "same PBKDF2 everywhere" rule, and `bin/pos_migrate.dart` and the cloud contract already speak PBKDF2). PostgreSQL has no built-in PBKDF2. **[ASSUMED]**

The legacy PIN keeps its client-side check **unchanged in Slice D**; it moves behind the same function in Slice E
when the till loses SELECT on the hash columns.

## D2. Schema — migration 54 (`'staff sign in with a password'`)

All additive, `IF NOT EXISTS`, so every existing row stays valid and a rerun is a no-op.

```sql
ALTER TABLE pos_staff
  ADD COLUMN IF NOT EXISTS password_hash        text,            -- versioned, see below; NULL = no password yet
  ADD COLUMN IF NOT EXISTS password_set_at      timestamptz,
  ADD COLUMN IF NOT EXISTS must_change_password boolean NOT NULL DEFAULT false;

-- Failure counters, persisted (not in memory). Keyed by what was typed, lower-cased,
-- so an unknown name is throttled exactly like a real one (no enumeration).
CREATE TABLE IF NOT EXISTS pos_auth_attempts (
  restaurant_id bigint      NOT NULL,
  subject       text        NOT NULL,        -- lower(trim(username)) or 'terminal:<uuid>'
  failures      integer     NOT NULL DEFAULT 0,
  lockouts      integer     NOT NULL DEFAULT 0,
  locked_until  timestamptz,
  last_failure  timestamptz,
  PRIMARY KEY (restaurant_id, subject)
);
-- Internal-only values for fake salts. One row, generated at migration time.
CREATE TABLE IF NOT EXISTS pos_auth_pepper (id boolean PRIMARY KEY DEFAULT true CHECK (id), pepper text NOT NULL);
INSERT INTO pos_auth_pepper (pepper) VALUES (gen_random_uuid()::text || gen_random_uuid()::text) ON CONFLICT DO NOTHING;
```

Rationale: `password_hash` is a **new column**, not a widened `pin_hash`. `pin_salt/pin_hash` are `NOT NULL`,
written by four writers (wizard `seedOwner`, `pos_migrate --seed`, `BootstrapSeeder`, `PostgresStaffDirectoryRepository`),
and POS-BE-024 owns their meaning in cloud. Touching them would break the cloud contract and the seeder.

**Versioned format** (one text column, parsed by one Dart class and one SQL `split_part`):

```
pbkdf2-sha256$600000$<salt_b64>$<key_b64>
```

* `600000` iterations (OWASP 2023 figure for PBKDF2-HMAC-SHA256). **[ASSUMED]** ~0.3-0.6 s in pure Dart on a till PC; once per session, but run in `Isolate.run` so the UI does not freeze. Measure on the slowest supported till before fixing the number; it is stored per row, so it can be raised later (`rehash on next sign-in`).
* Legacy PIN rows are *not* rewritten: they stay `(pin_salt, pin_hash)` at 120 000. "Old 4-digit PIN hashes still verify during migration" is satisfied by leaving them alone and keeping the PIN path.
* New Dart class `StaffSecret` in `lib/core/security/staff_secret.dart` (pure Dart): `encode`, `parse`, `derive(password, saltB64, iterations)`, `isStale(minIterations)`. `PinHash` stays as is (plus nothing). Do **not** change `PinHash.iterations`: the cloud verifier and POS-BE-024 depend on 120 000.

## D3. DB functions (migration 54, `SECURITY DEFINER SET search_path = pg_catalog, public`, EXECUTE granted to the till group only)

Pattern copied from migration 12/42. Each begins `REVOKE ALL ON FUNCTION ... FROM PUBLIC` then `GRANT EXECUTE ... TO "<till role>"` — grants for functions belong in `LocalBootstrap.tillGrants` (it re-runs on `upgrade`), **not** in the migration, because the role name is unknown to migrations (same reason existing table grants live there).

| Function | Purpose |
|---|---|
| `pos_auth_params(p_restaurant bigint, p_username text) RETURNS TABLE(kind text, iterations int, salt text)` | Returns the real salt/iterations for a password account. For an unknown username, an inactive account, or one with no password, returns a **deterministic fake salt** `encode(sha256(convert_to(pepper||lower(p_username),'UTF8')),'base64')` and the default iterations, so the response shape and timing do not reveal existence. `kind` is `'password'` always for this function (the client does not learn "has no password"). |
| `pos_auth_verify(p_restaurant bigint, p_branch bigint, p_username text, p_terminal uuid, p_key text) RETURNS TABLE(ok boolean, staff_id bigint, must_change boolean, locked_until timestamptz)` | Checks lockout rows (username and terminal) **first**; computes comparison as `sha256(convert_to(stored_key,'UTF8')) = sha256(convert_to(p_key,'UTF8'))` (compare digests so a byte-by-byte `=` cannot leak a prefix); on failure increments counters (5 failures -> lockout 30 s, doubling to 15 min; numbers **[OPEN]**), on success resets them. **Always** performs the same work for unknown users (compare against a constant dummy). Returns `ok=false` for inactive, branch-mismatched, locked, unknown, or no-password alike; `locked_until` is non-null only when the *caller's own* counter is locked (the UI may show a wait; it does not say why). |
| `pos_set_password(p_restaurant bigint, p_staff bigint, p_proof_kind text, p_proof_key text, p_new_hash text)` | Self-service set/change. `p_proof_kind='pin'`: `p_proof_key` is the legacy PBKDF2 key, compared with `pin_hash`; `'password'`: compared with the current `password_hash` key. Validates `p_new_hash` format (prefix, iterations >= 600000 minimum configurable constant, base64 lengths). Sets `must_change_password=false`, `password_set_at=now()`. Counts a wrong proof against the same lockout. Inserts the audit row itself (`staff.password.set`, never the value). |
| `pos_staff_has_password(p_staff bigint)` is **not** added | Would leak existence. The lock screen decides "set a password now" from the result of a *successful* PIN sign-in, which already returns the staff row; `PosStaff` gains `hasPassword` / `mustChangePassword` from the same query (column read by the existing sign-in SELECT through the function result, not the table). |

**Why a function and not a column-scoped UPDATE**: offline `tillGrants` REVOKEs `INSERT/UPDATE ON pos_staff` on purpose (a stolen till credential must not point a row at the owner role or overwrite a hash). A column grant on `password_hash` would reintroduce exactly that. The function proves knowledge of the *old* secret first.

**Admin reset** (manager/owner sets someone else's password, or technician reset) stays on the admin connection: `StaffDirectoryRepository.resetPassword(by, staffId, temporaryPassword)` mirrors `resetPin` (`postgres_admin_repositories.dart:768`) including the `OwnerPinIsTheirs` rule (rename `OwnerSecretIsTheirs`; keep the old class for strings until removed), writes `password_hash` + `must_change_password = true`, audits `staff.password.reset`. Admin can already UPDATE `pos_staff` (`administrativeGrants`), so **no new grant**.

## D4. Password policy (all constants in `lib/core/security/password_rules.dart`)

* Minimum **10** characters, maximum **128** (a bound for DoS on PBKDF2, not for strength). **[OPEN]** numbers: a cashier typing at speed vs. a restaurant PC; 8 is the common floor, 10 proposed because there is no second factor.
* No composition rules (no "one digit, one symbol"); no trimming, no case folding of the password; Unicode accepted as typed. **[ASSUMED]** no NFC normalisation in Dart core; an Arabic keyboard layout producing different code points for the same glyph across machines is a real risk -> document and test with an Arabic string on both OS targets; if it bites, normalise to NFC on both client and (future) cloud side together.
* Rejected: equal to username or name; all one character; in a small bundled list (`12345678`, `password`, `qwerty`, `00000000`, restaurant name, ...). Not a breach database.
* Reuse: refuse the previous password only (cheap: compare derived keys against the old row inside `pos_set_password`).
* **Username lookup is not secret** (the lock screen already lists name tiles — see D6; this is the accepted UX). What must not leak is *which* of "wrong username / wrong password / account locked / no password set / inactive". One generic string `wrongUsernameOrPassword` for all, plus a neutral "try again in N seconds" only for the caller's own counter.
* Max-attempt behaviour: per-username counter **and** per-terminal counter, both persisted. Per-username lockout lets an attacker lock out the owner; mitigations: lockout capped at 15 min (as Admin Mode), the terminal counter is what actually slows enumeration, and a technician can clear counters (`pos_migrate --clear-lockouts`). **[OPEN]** the numbers (Q18).

## D5. Migrating existing accounts (the owner must never be locked out)

Policy switch `StaffAuthPolicy` in `lib/core/config/staff_auth_policy.dart` (pure Dart), values:

| Value | Meaning |
|---|---|
| `pin` | Today's behaviour. **Forced for `cloud` mode until the backend contract exists.** |
| `pinOrPassword` | Both accepted. A PIN sign-in by someone with no password shows a **"Set your password"** screen they can postpone (counter, N skips or until a date, **[OPEN]**). **Default for every upgraded install.** |
| `password` | Password required; PIN no longer unlocks staff sign-in (it remains the supervisor/quick-unlock secret, see D6/D7). **Default for fresh offline installs.** |

Storage: `pos_settings` row `(scope='restaurant', key='staff_auth_policy')`, authored in Management > Staff by `settings.manage` over the admin connection (existing `PostgresSettingsRepository` is till SELECT-only; the write belongs to an admin repository). The effective policy is `min(strictness(mode default), stored value)` and cloud is clamped to `pin` in code, so a copied database cannot switch a cloud till to passwords the platform cannot supply. **[ASSUMED]** `pos_settings` string `value` is enough; check `PostgresSettingsRepository` for the key naming convention before adding.

Sequence for an upgraded offline install:
1. Upgrade -> migration 54 adds columns. **Nobody's sign-in changes.**
2. `pinOrPassword`: first PIN sign-in of each person offers "Set your password" (a PIN that just worked is the proof; `pos_set_password(proof_kind='pin')`). The owner is therefore never asked for something they cannot supply.
3. Once every active account has a password, Management shows "Require passwords" (flips to `password`). Never automatic.
4. Forgotten password: staff -> any manager with `staff.manage` resets to a temporary one (`must_change_password`); owner -> **technician reset**: `dart bin/pos_migrate.dart --reset-staff-password <username>` (admin credential; works from the main device) and an in-app "Technician recovery" dialog that asks for the typed `pos_admin` password (never read from disk after slice B). Both write an audit row (`actor_name = 'technician'`). Design this CLI/dialog **in the same commit as the policy flip**, never later.
5. Safety net: if the policy is `password` and the database has **no** active account with `password_hash IS NOT NULL` holding `admin.enter`, sign-in falls back to `pinOrPassword` (cannot lock the whole restaurant out via a bad flip). Test it.

## D6. Sign-in UI and the idle lock — recommendation, and the product trade-off

Current flow: lock screen = name tile/field + 4-digit pad that submits on the 4th digit (`PinRules.length`). It is built for speed and a shared till.

**Recommendation (a 3-tier "session" model): [OPEN — product decision #1]**

| Moment | Credential | Why |
|---|---|---|
| Start of shift / start screen / different person / after logout / after 12 h / after the app restarts | **Username + password** (full) | This *is* "once per session"; produces the DB session (Slice E token). |
| **Idle lock (5 min) for the same person** | **Re-enter PIN (quick unlock) or password**, user chooses; PIN only if they have one set | A cashier stepping away between tickets re-enters four digits, not a 10-character password, ~20 times a shift. |
| Different person picks up a locked till | Full password | Handover = new session. |

Trade-off to put to the owner: strictly reading the accepted decision ("username+password once per session") a quick PIN is *part of the same session*, and the sign-in already established who is at the till. With **password-only unlock** every idle lock costs the cashier ~6-10 s of typing at speed, queues at the counter, and the practical result is people turning the lock off or sharing one logged-in session — worse security than a PIN. A PIN quick-unlock is only defensible while the verifier is **not readable by the till role** and **lockout is persisted** (both true after D3/E); a 4-digit PIN protected by neither is the weakness SECURITY_AND_RECOVERY §7.1 records. Cost of the recommendation: two secrets per person to manage, and the PIN remains a (weaker) secret. **Do not implement quick-unlock until the owner picks.** Ship the idle lock itself regardless: the 5-minute rule is accepted.

Implementation sketch (coordinate with the in-flight work):
* Idle detection: one global `Listener` (pointer) + `HardwareKeyboard` handler at the app shell, resetting a `Timer`; pattern already in `admin_activity_watch.dart`. Do **not** lock while a payment/print/sync call is in flight; lock after it returns. Lock closes all overlays (the lock screen already does) and keeps the open ticket in memory/parked, as `lock_screen.dart` documents.
* `LockScreen` splits into `LockScreen` (existing PIN pad, used for quick unlock + for `StaffAuthPolicy.pin`) and `SignInScreen` (username + password field, `TextField obscureText`, Enter submits, show/hide toggle). The "Back" action signs out (existing behaviour).
* The name tiles currently list **every** active staff (`signInCandidatesProvider`). With passwords keep tiles (same exposure as today, accepted UX) but **[OPEN #7]** a restaurant may want tiles off, which leaves a username-guessing surface; the persisted lockout bounds it.
* Password field must work with the on-screen keyboard on touch tills and with the Arabic layout (RTL `TextDirection` auto, but mask dots LTR).

## D7. Supervisor override and Admin Mode keypad — keep or change?

| Surface | Proposal | Reason |
|---|---|---|
| Supervisor override (lend `discount.apply`, `order.refund`, ...) | **Keep the 4-digit PIN keypad**, but (a) require the approver's **username** (today `byPin` returns "whoever holds this PIN", and two people sharing a PIN get the lower id: the lock-screen comment already calls this wrong) — pick from tiles of people who hold the capability, then PIN; (b) lockout persisted (today 5 tries in the dialog only); (c) in Slice E the approval becomes a DB-verified `pos_approvals` row (see E6). **[OPEN #2]** | An approval is an in-person act with the supervisor standing at the till; a 10-character password per refund destroys the "walk over and tap" workflow the SRS describes. PIN is acceptable *because* it cannot reach `critical` capabilities (`mayBeLent`). |
| Admin Mode (`admin.enter`) and forced terminal reset (`checkStaffPin`) | **Change to username + password** once `StaffAuthPolicy` >= `pinOrPassword` and the person has a password. A person with no password keeps PIN until they set one. `AdminSessionController.signIn` gains a `secret` parameter and `kind`; `checkStaffPin` becomes `checkStaffSecret`. **[OPEN #2]** | Critical capability; the ADR says technician-only actions must be enforced beyond hiding UI, and Admin Mode in-memory lockout is bypassed by a restart (Doc §7.2). Move lockout to `pos_auth_attempts`. |
| Setup-wizard manager verification (`connect`, `registerManually`) | Password via `pos_auth_verify` when the policy allows, else PIN. | Same function, same lockout; today it has none. |

## D8. Cloud mode — what the backend must change, and the safe POS-only scope now

**Facts.** The platform delivers `staff[].pin` only; POS-BE-024 is `READY` and says PIN is exactly 4 ASCII digits, "never accepted by login", delivered only through the bootstrap bundle, and the dashboard refuses anything else. The seeder overwrites `pin_salt/pin_hash` on every bootstrap. Staff in cloud mode are **platform-authored** (`ManagedByPlatform` refusals in the admin repository). So a local-only password in cloud mode would be (a) overwritten or ignored by the next bundle, (b) invisible to the dashboard, and (c) not recoverable by the platform's reset flow. Therefore username + password in cloud is **backend-dependent**: roadmap rule = backend half in the same phase **[BE]**.

**Contract change needed (proposed `POS-BE-0xx`, number to be assigned in `BACKEND_TO_POS.md`):**
1. Dashboard: `PUT /api/dashboard/staff/{staff}/pos-password {password}` and `DELETE`, `can:staff.update` or own row; write-only; audited (action, never value); bumps `config_version`. The password policy is validated server-side (same constants as D4 — put them in the contract so both ends agree, like the PIN length lesson in POS-BE-024).
2. Storage: `users.pos_password_salt/pos_password_hash/pos_password_iterations` (nullable, `forceFill` only, never in `$fillable`, never serialised by `UserResource`) — **separate from the dashboard login password and from the PIN**; the dashboard hash must never be shipped.
3. Bundle: `staff[].password = {algorithm:"pbkdf2_sha256", iterations:600000, salt, hash} | null`, and `staff[].must_change_password: bool`; frozen-key additive, `staff[].pin` unchanged for old tills. Version-negotiate via an additive `staff_auth` capability flag in the bundle so an old till ignores it and a new till on an old platform keeps PIN.
4. Change flow: either dashboard-only (simplest, no upstream write) **or** a device-credential endpoint `PUT /api/pos/staff/{id}/password` for till self-service with idempotency (POS-BE-007 style). **[OPEN #3]** — recommend dashboard-only first; then "forgot/change password" in cloud is a dashboard action and a till can't change it offline.
5. Revocation: setting null clears it at the next sync (as PIN today).
6. The `ON CONFLICT` list in `BootstrapSeeder._seedStaff` must start writing `password_hash` from `bundle` **only when the key is present** (absent key = "platform does not do passwords" -> leave local value / NULL). Test both.

**Safe POS-only scope now (no backend dependency):**
* **Offline: Slice D complete.** **Cloud: `StaffAuthPolicy` clamped to `pin`.**
* The **5-minute idle lock applies to both modes** (PIN re-entry in cloud) — pure POS work.
* Slice E (per-till roles, session tokens, guarded writes) works in cloud mode too, with the token minted from the **PIN** (see E5 - the sign-in function accepts `kind='pin'`).
* Schema columns/functions from migration 54 are mode-neutral; the cloud seeder never writes `password_hash`, so a cloud-then-offline migration (ADR-008) cannot be broken by them. **[ASSUMED]** ADR-008 (Offline->Cloud) will say platform becomes staff authority; a `password_hash` written offline will be superseded by the platform's on first bundle — decide whether it is preserved as `NULL`-safe. Raise in Phase 4.
* The switch is code (`StaffAuthPolicy.forMode(DeploymentMode)`), not data, so it cannot be flipped by editing a database row.

## D9. Files and functions to change (Slice D)

| File | Change |
|---|---|
| `lib/data/postgres/migrations.dart` | Migration **54** (D2/D3 SQL). Keep each function as one `r'''...'''` statement with `\$fn\$` quoting as migrations 12/42 do (the file mixes `\$fn\$` escapes in `'''` strings and `$fn$` in `r'''`; copy one style per statement, don't mix). |
| `lib/data/postgres/local_bootstrap.dart` | `tillGrants`: `GRANT EXECUTE ON FUNCTION pos_auth_params(bigint,text), pos_auth_verify(...), pos_set_password(...) TO "$role"`; **no table grants** for the new tables to the till (they are only reached through the functions) — which also keeps `grants_cover_usage_test` quiet only if no till repository file names `pos_auth_attempts`/`pos_auth_pepper`. Add the three function names to `administrativeGrants` too (admin gets both lists anyway). |
| `lib/core/security/staff_secret.dart` (new), `password_rules.dart` (new) | Format, derive (isolate), validation. Unit-tested without Flutter. |
| `lib/domain/repositories/repositories.dart` (`SessionRepository` ~826-848) | Add `Future<StaffSignIn> signInWithPassword({username, password, terminalId})` returning a sealed result (`Signed(PosStaff, mustChange)`, `Refused`, `LockedOut(wait)`, `Unreachable`) — data, not exceptions, matching `AdminSignIn`. Add `setOwnPassword(...)`. Keep `signIn/signInAs/verifyPin`. |
| `lib/data/postgres/postgres_directory_repositories.dart` | Implement via the functions: fetch params -> derive -> `pos_auth_verify` -> load the person with the **existing** SELECT narrowed by id (reuse `_match` row mapping + `_withGrants`; extract the row mapper). Map `PosDbException` (dns/tcp) to `Unreachable`. |
| `lib/data/postgres/postgres_admin_repositories.dart` | `resetPassword`, `setStaffAuthPolicy`; extend `createStaff`/`StaffDraft` with optional temporary password; `PinRules` use stays. |
| `lib/data/fakes/fake_repositories.dart:505-545`, `lib/data/unconfigured/unconfigured_repositories.dart:57-66` | Implement the new methods (fake: fixed username/password pair; unconfigured: refuse). |
| `lib/features/lock/lock_screen.dart` | Switch on `StaffAuthPolicy`; add `SignInScreen`; "set your password" interstitial route; lockout wait text. Keep keys `lock-back`, `lock-tile-*` (tests use them). |
| `lib/features/shift/presentation/shift_dialogs.dart:76-127` | Open-shift sign-in uses the same sealed result. |
| `lib/features/admin/application/admin_session.dart` | `checkStaffPin` -> `checkStaffSecret(kind)`, DB lockout instead of `_failures/_lockouts` (keep the in-memory as a client-side 2nd layer), `AdminSignIn` gains no new members (maps `LockedOut` to existing `AdminSignInLockedOut`). |
| `lib/features/admin/presentation/admin_sign_in.dart`, `management_staff_pane.dart` | Password field, "Reset password", policy toggle, "Passwords set: n of m", technician recovery dialog. |
| `lib/features/admin/presentation/supervisor_override.dart:319` | Approver picked by name then PIN (D7). |
| `lib/app/providers.dart` | `staffAuthPolicyProvider` (mode-clamped), idle-timer provider, wiring (grep names; do not read the import block). |
| `lib/core/l10n/app_strings.dart` | Strings below, in `AppStrings`, `EnStrings`, `ArStrings`. |
| `bin/pos_migrate.dart` | `--reset-staff-password <username>`, `--clear-lockouts`; seed paths (`--seed`, wizard `seedOwner`) may keep PIN until policy flips; **also** accept `--owner-password` for fresh offline installs. |
| `lib/data/cloud/bootstrap_seeder.dart` | **Unchanged in D** (state this in the commit message). |

**Strings (EN + AR; all new getters on the abstract class):** `signInTitle`, `usernameLabel`, `passwordLabel`, `showPassword`, `hidePassword`, `wrongUsernameOrPassword`, `tryAgainInSeconds(n)`, `tooManyAttempts`, `setYourPasswordTitle`, `setYourPasswordBody`, `newPassword`, `confirmPassword`, `passwordsDoNotMatch`, `passwordTooShort(min)`, `passwordTooCommon`, `passwordSameAsUsername`, `passwordSameAsPrevious`, `passwordChanged`, `remindMeLater`, `mustChangePasswordNow`, `quickUnlockWithPin`, `useYourPasswordInstead`, `lockedAfterInactivity` (exists?), `resetPasswordAction`, `resetPasswordTemporaryHint`, `passwordsSetCount(n,m)`, `requirePasswordsAction`, `requirePasswordsConfirm`, `staffAuthPolicyLabel`, `technicianRecoveryTitle`, `technicianRecoveryBody`, `adminPasswordTyped`, `onlyOwnerSetsOwnPassword`, `passwordsManagedByPlatform` (cloud), `capStaffManage` text update ("reset PINs and passwords"). Existing `wrongUsernameOrPin`, `enterYourPin` stay.

**Tests (Slice D).** All Dart-only ones must pass with no database (`flutter test`); integration ones self-skip.

* Unit: `staff_secret_test` (round trip; known vector for PBKDF2-SHA256 so a Dart/SQL/other-side mismatch is caught; reject malformed format; `isStale`), `password_rules_test` (length bounds, trivial list, Arabic string), `staff_auth_policy_test` (cloud clamped to `pin`; fallback when no admin holds a password).
* Widget: lock/sign-in screens per policy (`pin`: unchanged keys; `pinOrPassword`: set-password prompt after PIN; `password`: pad hidden); lockout wait text; generic error for every refusal kind (assert the *same string* for wrong user/wrong password/locked); idle lock timer with a fake clock (reuse `adminClockProvider` idea).
* Integration (tag `integration`, superuser is fine for functions): `staff_auth_functions_test` — correct/incorrect key; unknown user takes the same code path and returns `ok=false` with a fake salt that is stable per name and differs between names; lockout after N and doubling; reset on success; `pos_set_password` with a PIN proof, with a password proof, with a wrong proof (counts as failure); legacy PIN row unchanged after migration; migration idempotent; audit row has no secret.
* Integration, **real role** (copy `till_grants_enforced_test`): till role has EXECUTE on the three functions, **no SELECT on `password_hash`**, **no UPDATE on `pos_staff`**, cannot read `pos_auth_pepper`/`pos_auth_attempts` directly. `psql` as the role: `SELECT password_hash FROM pos_staff` -> `42501`.
* Update `till_grants_test` (statement list) and `grants_cover_usage_test` (nothing to add if no till repository names the new tables; if it does, allow-list them with a comment).
* Admin: `resetPassword` owner rule; `must_change_password` forces the interstitial; technician CLI reset (`migration_cli_test` style).
* Seeder: `cloud_bootstrap_test` — bundle without `password` leaves `password_hash` NULL; with a password key (future) round-trips.

## D10. Slice D risks

1. PBKDF2 at 600k in pure Dart on a weak till may take >1 s -> measure; isolate; consider the native `cryptography_flutter` only if needed (new dependency, needs signing review).
2. Sending `K` over a plaintext LAN is password-equivalent. D must not ship the password path before TLS-by-default, or must warn and require the audited TLS-off override. **Block on installer TLS work or ship D behind `pinOrPassword` where passwords are optional and documented as LAN-sensitive.**
3. `pos_auth_verify` increments counters on every wrong attempt: a tight loop from a stolen till role can lock any named account (DoS). Accepted trade-off; technician clear exists; the cap is 15 min.
4. Two SQL dialect problems when writing blind: `$fn$` quoting in Dart strings (see D9), and `RETURNS TABLE` column names colliding with variables (qualify every column). Needs a real PostgreSQL run.
5. Locale: password typed on different keyboard layouts (Arabic/English toggling mid-word). Test.
6. Two readers of the roster: `signInCandidatesProvider` and the name tiles show who works here; unchanged exposure, called out so nobody believes the "no enumeration" claim covers it.

---

# SLICE E — Per-till DB roles and guarded privileged writes

## E1. Honest framing of what is and is not achievable

* After E, a till role **cannot** write another terminal's rows, cannot rewrite what a staff member is, and cannot perform the listed privileged acts without a DB-verified identity and capability.
* A person at a till with the till's own role and a signed-in cashier session can still do what that cashier may do — as intended. The point is that Dart is no longer the only gate.
* The DB cannot see the Dart session, so identity is carried by a **short-lived opaque token minted by the DB at sign-in** (E5). A recovered role password alone is no longer enough to impersonate a manager.

## E2. Roles

| Role | Created by | Privileges |
|---|---|---|
| `pos_till` (existing) | installer (unchanged) | Becomes the **group**: keeps every grant from `tillGrants`. In step 3 (a later release) it gets `ALTER ROLE pos_till NOLOGIN`. Existing installs keep logging in as it until each till re-enrols. |
| `pos_t_<12 hex>` (new, one per terminal; `<12 hex>` = first 12 of the terminal UUID without dashes) | `pos_provision_terminal` (E3) at registration | `LOGIN`, `NOSUPERUSER NOCREATEDB NOCREATEROLE`, member of `pos_till` (inherit), `CONNECTION LIMIT 8` (pool is 4), `VALID UNTIL` unset. Password: 32 chars from a CSPRNG, generated **inside the function** and returned once. |
| `pos_enroll` (new, optional but recommended) | installer / `pos_migrate --provision` (superuser) | `LOGIN`; **only** `EXECUTE` on `pos_register_terminal`; no table access. Replaces "type the shared till password on a child" once the shared one is disabled. |
| `pos_provisioner` (new, **NOLOGIN, CREATEROLE**) | installer / `pos_migrate --provision` (superuser) | Owner of the provisioning functions only; has `ADMIN OPTION` on `pos_till` (`GRANT pos_till TO pos_provisioner WITH ADMIN OPTION`) and membership of `pg_signal_backend` (to terminate a revoked till's sessions). |
| `pos_admin`, `pos_backup`, `postgres` | unchanged | `pos_admin` still has no CREATEROLE. |

**Why a CREATEROLE-owned SECURITY DEFINER function** (answering "who can run `CREATE ROLE`"): `pos_admin` deliberately lacks CREATEROLE and a child registering from another PC does not hold the admin password at all. The function is the *only* place CREATEROLE is exercised, takes a terminal id (not a role name), builds the role name itself, and uses `format('CREATE ROLE %I ...')` / `%L`. In PostgreSQL 16 a CREATEROLE role may only grant memberships it administers, hence the `ADMIN OPTION` on `pos_till`. **[ASSUMED]** PG16 semantics (installer ships 16; on PG <= 15 CREATEROLE could grant any role including superuser membership; the installer must refuse < 16 for this feature).

**Superuser-only one-time step.** Creating `pos_provisioner`, `pos_enroll` and the functions' owner needs a superuser, once per cluster. Where it runs:
* Fresh Windows install: `installer/provision.ps1` (superuser password is in `install-credentials.json`) via `pos_migrate --provision`. *(Another agent owns `installer/` right now — hand them this contract; do not edit it from this task.)*
* Upgrade of an existing install: re-running `provision.ps1` ($fresh=false path reads the credentials file) or `dart bin/pos_migrate.dart --provision --superuser postgres` typed by the technician.
* Hand-installed PostgreSQL: the same CLI.
* If the step is not done, **the app keeps working on the shared `pos_till`** (see E9) and Management shows "Per-till roles not set up" — no hard failure.

## E3. Registration handshake (child registering from another machine, no admin password)

```
Child (no secrets)                          PostgreSQL
 1. connect as pos_enroll  (password = the "enrolment password" shown on the main device,
    or, during the transition, the legacy shared pos_till)   --------------------------->
 2. SELECT pos_auth_params(restaurant, mgr_username)      <- salt, iterations
 3. K = PBKDF2(mgr_password | PIN legacy)
 4. SELECT * FROM pos_register_terminal(
        p_restaurant, p_branch, p_name, p_install_id,
        p_mgr_username, p_mgr_kind, p_mgr_key)             --------------------------->
        inside (SECURITY DEFINER, owner pos_provisioner):
          - verify mgr credential exactly like pos_auth_verify (shared lockout counters);
            manager must hold terminal.manage (or staff.manage) [capability SQL, E5];
          - existing idempotent upsert into pos_terminals ON CONFLICT (restaurant_id, install_id);
          - seat check against the licence (the existing child seat count, see setup_controller);
          - if no role mapped for that terminal: CREATE ROLE pos_t_xxxx LOGIN PASSWORD <random>;
            GRANT pos_till TO it; INSERT pos_sys.terminal_roles; audit row;
          - if already mapped: ALTER ROLE ... PASSWORD <new random> (re-enrol) and audit it;
          RETURNS (terminal_id uuid, role_name text, role_password text)   <-----------------
 5. Child stores role_password in SecretStore (slice B), role_name in config, drops the
    enrolment/shared secret, reconnects as pos_t_xxxx, and verifies with SELECT pos_whoami().
```

* The manager's credential never leaves the child as a password, only `K`. Wrong credentials / locked / no seat / unknown branch all return the same refusal shape as today (`CREDENTIALS_REJECTED`) so nothing new leaks.
* **Main device**: same function, called with the `pos_admin` connection it already has at setup time (`pos_admin` gets EXECUTE too).
* **Cloud pairing code path** (`claimByCode`): stays; after a successful claim the same role-creation function is called with the claim as authority (function takes `p_authority = 'pairing:<terminal>'` — the claim already proves the terminal row). Keep to one function with two proof kinds. **[ASSUMED]** the claim happens on the till's DB connection; read `claimByCode` again before wiring.
* **Revocation**: `pos_revoke_terminal(p_token, p_terminal)` requires `terminal.manage`; does `ALTER ROLE ... NOLOGIN`, sets `revoked_at`, `pg_terminate_backend` for that role's pids (needs `pg_signal_backend`), audits. Re-enrol re-enables (`LOGIN`, new password).
* **Rotation**: `pos_rotate_my_password()` callable by the till role itself: `ALTER ROLE session_user PASSWORD <new random>` via `format('%I','%L')`, returns the new password; the till writes it to `SecretStore` **then** confirms by reconnecting; on failure it keeps the old one valid (the function returns after commit; the Dart side writes the secret before it drops the old pool). Schedule: on demand + at re-enrolment. Not on a timer in v1.
* **Where the secret lives**: slice B's `SecretStore` (`lib/data/config/secret_store.dart`: `read/write/delete(key)`), new key `pos_terminal_role_password`; `config.json`/`DeploymentConfig.databaseUser` holds only the role name. `KeyedSecretStore` already adapts a key to `PosDbSecretStore`, which `PosDatabase` consumes — **no change to `pos_database.dart` pool code** beyond the user name from config. The shared password is deleted from the store on successful re-enrolment.

## E4. Binding `terminal_id` server-side

`pos_sys.terminal_roles(role_name text PRIMARY KEY, restaurant_id bigint, terminal_id uuid NOT NULL REFERENCES pos_terminals(id), enrolled_at timestamptz, revoked_at timestamptz)` — in a **separate schema `pos_sys`** (rationale: E9 backup).

```sql
CREATE FUNCTION pos_sys.pos_terminal_id() RETURNS uuid
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = pg_catalog, pos_sys AS
$$ SELECT terminal_id FROM pos_sys.terminal_roles
    WHERE role_name = session_user AND revoked_at IS NULL $$;
```

* **`session_user`, not `current_user`**: inside a SECURITY DEFINER function `current_user` is the owner. Role-level `ALTER ROLE ... SET pos.terminal_id` was rejected: any session may `SET` it itself.
* Guard triggers `BEFORE INSERT` on `pos_orders`, `pos_shifts`, `pos_refunds`, `pos_cash_movements`, `pos_cash_drawers`, `pos_print_jobs` (text compare), `pos_audit_events`, and `pos_terminals` (UPDATE restricted to its own row): `IF pos_sys.is_guarded_session() THEN IF NEW.terminal_id IS DISTINCT FROM pos_sys.pos_terminal_id() THEN RAISE ... USING ERRCODE='42501'`. Not applied to `pos_backups` (written by backup service; verify before including).
* `pos_sys.is_guarded_session()` = `session_user = 'pos_till'` -> **false** during step 1-2 compat (legacy shared role is not blocked), OR `session_user` is a direct member of group `pos_till` (via `pg_auth_members` join, **not** `pg_has_role`, which is true for every superuser and would fire the guard in the superuser-run test suites) -> true. A member role with **no mapping** or a revoked one -> `pos_terminal_id()` NULL -> every write refused. That closes the "created role but forgot the mapping" bypass.
* Cloud seeder, outbox drain and the backup writer run on the till role but are not staff acts and write non-`terminal_id` tables or a fixed system terminal; verify `pos_cloud_state`, `pos_outbox`, `pos_sync_outbox` are **not** guarded (they have no terminal_id or are written system-wide).

## E5. Staff identity inside the DB: session token

`pos_sys.sessions(token_hash bytea PRIMARY KEY, restaurant_id, staff_id bigint, terminal_id uuid, kind text CHECK (kind IN ('password','pin')), created_at, last_seen_at, expires_at, ended_at)`. No grants to the till; reachable only via functions.

* `pos_sign_in(p_restaurant, p_branch, p_username, p_kind, p_key) RETURNS (ok, staff_id, token, must_change, locked_until)` = `pos_auth_verify` + mint: `token := encode(sha256(...))`-hashed storage; the plaintext token is `gen_random_uuid()::text || gen_random_uuid()::text` (CSPRNG-backed in PG13+; **[ASSUMED]** server >= 13), returned once, **held only in memory by the Dart `PosStaff` session** (new field `DbSession`). Bound to `pos_terminal_id()`; a token minted from till A is refused from till B's role. `kind='pin'` verifies against `pin_hash` (legacy, 120 000, 4 digits) so cloud mode gets tokens too.
* `pos_end_session(token)` on logout/idle lock for a *different* person; idle lock for the same person keeps the token (the "session" outlives the lock — product decision #1) with `expires_at = last_seen + 8h` sliding **[OPEN]**.
* Capability check in SQL: `pos_sys.staff_has(p_staff, p_cap) RETURNS boolean` = union of `pos_roles.capabilities` for `role_id` + `pos_staff_roles` + legacy `pos_staff.capabilities`, then `ALLOW` overrides, minus `DENY` overrides, all passed through the **same canonical rename and implied-key rules** as `PosCapability.canonical/_implied` (a SQL table `pos_sys.capability_aliases(old, new, implies)` seeded from `PosCapability._renamed/_implied`), and `is_active`. Limits: `pos_sys.staff_limit(p_staff, p_key)` mirrors `PermissionLimit.tightenedBy` (per-field minimum across roles and personal).
* **This duplicates `PermissionResolver` in SQL; it is the largest correctness risk in Slice E.** Mandatory mitigation: a parity test (integration) enumerates `PosCapability.all` x the four `SystemRoles` x a few overrides/limits and asserts `staff_has` equals `PermissionResolver`. A second table `pos_sys.capability_meta(cap, risk, overridable)` generated from `PosCapability._risk/overridable` is checked by the same test; any new capability that is not in both sides fails the build.

## E6. Privileged writes: two patterns, and which act uses which

**Pattern A — guard trigger + transaction-local token (recommended first; minimal rewrite).**
The Dart repository keeps its existing multi-table inserts. `PosDatabase.runTx` gains `runTxAs(config, token, action)` which executes `SELECT set_config('pos.session_token', @t, true)` as the first statement (`true` = transaction-local, so a pooled connection cannot leak a token to the next user — **must** be asserted in a test). A `BEFORE INSERT/UPDATE` trigger on the protected table, active only for guarded sessions (E4), reads `current_setting('pos.session_token', true)`, resolves it via `pos_sys.session_staff(token)` (checks expiry, `terminal_id = pos_terminal_id()`, `is_active`), checks `staff_has(...)`, **forces/validates the actor columns** (`refunded_by`, `voided_by`, `opened_by`, `closed_by`, `staff_id`, `actor_staff_id`) and, where an approval is needed, that a valid unspent `pos_sys.approvals` row exists. This is the same shape as the migration-12 triggers and turns Dart-only checks into DB-enforced ones **without reimplementing refund/void logic in plpgsql** — important because I cannot run PostgreSQL.

**Pattern B — SECURITY DEFINER function with the table grant revoked (use where there is no existing multi-statement Dart logic, or the act is intrinsically a DB act).** Signature always starts `(p_token text, ...)`.

| Act (capability) | Today | Pattern | Function / trigger |
|---|---|---|---|
| Void order (`order.void`) | column UPDATE `status/voided_by/void_reason_id/void_note` on `pos_orders` (`PostgresOrdersRepository`) | A now; B (`pos_void_order`) in E-later | trigger `pos_orders_guard`: transitions to `VOIDED` need `order.void` or an approval; `voided_by = session staff`. Other column updates (invoice number write-back, `business_day_id`) pass untouched. |
| Void line after send (`order.item.delete_after_send`) | UPDATE `voided_*` on `pos_order_lines`, INSERT `pos_order_line_events` | A | trigger on `pos_order_lines` + `pos_order_line_events` INSERT (`staff_id` forced). |
| Refund (`order.refund`, `refund.max`) | INSERT `pos_refunds/_lines/_payments` | A | trigger on `pos_refunds`: `refunded_by = session`; amount <= `staff_limit(refund.max)` else approval whose approver is a **different** person holding `order.refund` (matches `PostgresRefundsRepository` second-person rule at line ~72). |
| Discount beyond cap (`discount.apply`, `discount.max`) | INSERT `pos_order_discounts` | A | trigger on `pos_order_discounts`; compares to `staff_limit('discount.max')` (bp and minor), else approval. **Open gap: the UI-only discount gate (Doc §7.3) is closed here for persisted discounts only — an in-memory ticket discount that never hits `pos_order_discounts` before `pos_orders` insert is closed by validating on the `pos_orders` insert that total discount per row <= cap (needs the line columns; read `postgres_orders_repository.dart` first) [ASSUMED].** |
| Price override (`price.override`) | line price comes from the client on `pos_order_lines` INSERT | A | trigger on `pos_order_lines` INSERT: `unit_price_minor` must equal the catalogue/branch price row unless the line carries `price_overridden` and the session has `price.override`/approval. Needs a `price_overridden` flag column or an existing equivalent — **[ASSUMED] check the line schema; if no column exists this needs a migration and a Dart change, and is the highest-uncertainty guard.** |
| Payment removal (`payment.remove`) | operates on the in-memory/parked ticket before settlement | Not a DB act; guard at `pos_order_payments` INSERT is meaningless. Left as Dart + audit; **document the residual** | n/a |
| Cash movement (`cash.movement`, `cash.pay_out.max`) | INSERT `pos_cash_movements` | A | trigger: `staff_id = session`, pay-out limit, approval for over-limit; open-without-sale needs `cash.open_without_sale`. |
| Shift open/close (`shift.open/close`, another's drawer) | table-wide UPDATE on `pos_shifts` | A now (trigger: `closed_by = session`; closing another's shift needs `shift.close` + approval); then **narrow the grant to column-scoped UPDATE** (like `pos_orders`) | Migration + grant change in the revoke step. |
| Day close / force close (`day.close`, `day.force_close`) | column UPDATE on `pos_business_days` | A | trigger. |
| Settings (`settings.manage`) | till SELECT only; written on admin connection | none needed | Already not a till write. State it. |
| Staff admin, role editor (`staff.manage`) | admin connection; till has no write | none needed | Cloud seeder writes `pos_staff` on the till role: **change it** to call `pos_seed_staff(jsonb)` (SECURITY DEFINER, authority = "cloud main device" role) and revoke `INSERT/UPDATE ON pos_staff` from `pos_till` in cloud too (see Doc §4 "point a row at the owner role"). Largest cloud-only item; needs the bootstrap tests. **[OPEN #5]** |
| Backup/restore (`backup.manage`) | pg_dump via `pos_backup`/admin; restore on admin connection | none | Technician types `pos_admin`; slice B removes it from disk. Also: `pos_backups` INSERT stays (till), triggers keep it append-only. |
| Terminal reset / revoke (`terminal.manage`) | `TerminalReset.run()` client-side + `pos_terminals` UPDATE | B | `pos_revoke_terminal`, `pos_register_terminal` (E3); remove `UPDATE ON pos_terminals` from the till group except its own `claimed_at`/heartbeat columns (column-scoped). |
| Held-row release (P0-3) | column UPDATE `quarantined_at, quarantine_code` on `pos_outbox`, `pos_sync_outbox` | B | `pos_release_quarantined(p_token, p_table, p_id)` requires `terminal.manage`; audits. |
| Audit insert | INSERT with client-supplied actor | A | `BEFORE INSERT` trigger: when guarded, `terminal_id := pos_terminal_id()` (overwrite, not reject), `actor_staff_id`/`actor_name` must equal the session staff **unless** `action` is in a small system whitelist (`auth.failed`, `sync.*`, `backup.*`) where actor_staff_id may be NULL; hash chain (E7). |

**Approvals (the supervisor lending a capability).** `pos_approve(p_token, p_approver_username, p_approver_kind, p_approver_key, p_capability, p_subject text) RETURNS bigint` verifies the approver (shared lockout), requires `capability_meta.overridable AND risk <> 'critical'` and `staff_has(approver, cap)` and `approver <> requester`, inserts `pos_sys.approvals(id, requester, approver, capability, subject, expires_at = now()+2 min, spent_at NULL)` and returns its id. The guard trigger spends it atomically (`UPDATE ... SET spent_at = now() WHERE id = $1 AND spent_at IS NULL AND subject matches RETURNING`). The Dart `Approval` object gains `approvalId`; the repository passes it via a second transaction-local setting `pos.approval_id`. This turns "not a cryptographic token" into a DB-verified single-use record without changing the UX.

## E7. Audit-log immutability

* Today: INSERT+SELECT grant, `BEFORE UPDATE OR DELETE` and `BEFORE TRUNCATE` triggers (mig ~519), owner `pos_admin` can drop them, restore recreates the table, no chain.
* Improvement 1 (migration, safe): add `seq bigint`, `prev_hash bytea`, `row_hash bytea` to `pos_audit_events`; a `BEFORE INSERT` trigger (`SECURITY DEFINER`) takes `SELECT ... FROM pos_sys.audit_head WHERE restaurant_id = NEW.restaurant_id FOR UPDATE`, sets `seq = head.seq + 1`, `prev_hash = head.hash`, `row_hash = sha256(prev_hash || canonical-text(row))`, updates the head. This serialises audit inserts per restaurant (cost: a short row lock per audit event; **[ASSUMED]** acceptable at POS volumes; the refund trigger already locks rows the same way). Rows before the migration have NULL hashes; the chain starts with a genesis row.
* `pos_sys.audit_verify(p_restaurant) RETURNS TABLE(first_bad_seq bigint)`; `PostgresBackupRepository`/`BackupService` records the **head hash** in `pos_backups` at each backup, and restore re-verifies the restored chain and the head against the backup record (ADR-006 "restore re-verifies the chain"). The backup record gives a poor-man's external anchor; an off-box anchor is still open.
* Improvement 2 (optional, superuser): an **event trigger** forbidding `ALTER/DROP TRIGGER` and `DISABLE TRIGGER` on `pos_audit_events` for non-superusers. Event triggers can only be created by a superuser, so it belongs to the same one-time provisioning step as the roles; `pos_admin` (table owner) is then actually blocked. Honest limit: a superuser (the `postgres` password, installer-only) can still do anything; the chain detects it.
* Two honest limits to write in the UI/docs: a restore from an older backup rolls the chain back (the pre-restore snapshot and the `backup.restored` row record it); an attacker with `postgres` can rebuild a whole chain.

## E8. pg_hba

Nothing is required for functionality (`provision.ps1:158-168` already admits private ranges with scram). Hardening, owned by the installer agent:
```
hostssl xorder_pos +pos_till    192.168.0.0/16 scram-sha-256     # group membership, covers every pos_t_*
hostssl xorder_pos pos_enroll   192.168.0.0/16 scram-sha-256
hostssl xorder_pos pos_backup   127.0.0.1/32   scram-sha-256     # backups run on the main device
host    xorder_pos pos_admin    127.0.0.1/32   scram-sha-256     # [OPEN #6] Management only on the main device
host    all        all          0.0.0.0/0      reject
```
`+pos_till` works because the per-till roles are members of the group. `[OPEN #6]`: restricting `pos_admin` to loopback ends "Management from a child" and is the real fix for "the admin password lives on a child's disk"; it is a product change.

## E9. Backward compatibility, the three-step migration plan, rollback

**Step 1 (release N) — add, change nothing for existing tills.** Migration **55** `'per-till roles: schema pos_sys, mapping, sessions, functions'` creates `pos_sys` schema, `terminal_roles`, `sessions`, `approvals`, `capability_aliases/meta`, `audit_head`; the functions; the guard triggers in **compat mode** (guard only for sessions that are mapped group members; `session_user = 'pos_till'` is exempt); audit hash chain columns (migration **56**). `tillGrants`: `GRANT USAGE ON SCHEMA pos_sys`, `GRANT EXECUTE` on the callable functions (no table grants in `pos_sys`). Installer/`pos_migrate --provision` creates `pos_provisioner`, `pos_enroll`. **App still connects as the shared `pos_till`, without tokens.** Old binaries on other tills keep working (they are exempt). Rollback: nothing to do (additive); drop the triggers by a down-script only if the guard misfires.

**Step 2 (release N+1) — switch app code.** Sign-in mints a token (`pos_sign_in`); repositories use `runTxAs`; the child/main registration calls `pos_register_terminal` and the till reconnects as `pos_t_*`. Tills upgrade and re-enrol one by one; each one is independent. Compat trigger rule: a token is **optional while the connecting role is the legacy `pos_till`**; **mandatory for mapped roles**. So a till that has re-enrolled is enforced, one that has not is exactly as before. A mixed-version LAN works. Rollback of one till: re-enrol it onto the shared credential is **not offered** (that defeats the point); instead the technician `ALTER ROLE pos_t_x NOLOGIN` and re-enrols; the table of mapped roles is the inventory.

**Step 3 (release N+2 or later; never in the same release as step 2) — revoke the shared path.** Only when the main device shows "all N terminals enrolled" (count of `terminal_roles` rows vs licence seats): `ALTER ROLE pos_till NOLOGIN`; narrow table-wide UPDATE/INSERT grants on `pos_shifts`, `pos_terminals`, `pos_audit_events` etc. to the column-scoped / function forms; `REVOKE SELECT (pin_hash, pin_salt, password_hash) ON pos_staff FROM pos_till` (this needs the table-level SELECT replaced by a column list GRANT: **a table-level `GRANT SELECT` cannot be partially revoked by a column REVOKE**, so the migration must `REVOKE SELECT ON pos_staff` then `GRANT SELECT (all other columns)` — and every future column added to `pos_staff` must be added to that list, a maintenance trap that needs a test; see below); switch the PIN check to `pos_sign_in(kind='pin')`. The cloud `cloudSeeding` write on `pos_staff` moves behind `pos_seed_staff`. **Rollback:** `ALTER ROLE pos_till LOGIN` restores the old path in seconds; kept for one release after step 3 before the group role's direct write grants are removed (a *fourth* step, so a failed step 3 is reversible by one statement).

**Dependencies on other slices.** Needs slice B's `SecretStore` to hold the role password (never the file store: if `secrets.json` is still the store, a per-till password in plaintext is no better than the shared one for that machine, but it is revocable — which is itself the gain; do not block on B for steps 1-2, do block step 3's "remove shared password from disk"). Needs the installer for the superuser step and TLS.

**Backup and restore.**
* `pg_dump` does not dump roles; `pg_restore --clean --no-owner` restores table ACLs (GRANTs) and re-creates functions **owned by the restoring user (`pos_admin`)** because of `--no-owner`. A `pos_admin`-owned provisioning function has no CREATEROLE -> enrolment would break after every restore. **Decision: keep `pos_sys` outside the dump** (`pg_dump -N pos_sys`, `pg_restore -N pos_sys` — `--exclude-schema` exists for both in PG16 **[ASSUMED]**; edit `pg_archive.dart:226-244` and the dump command). Consequences: the mapping, the sessions and the audit head survive a restore, which is exactly right because the *roles* (cluster-level) survive it too. Triggers in `public` that call `pos_sys.*` are recreated by the restore and still resolve. **If excluding the schema proves awkward, fallback:** run `pos_migrate --provision --reown` as the post-restore step and gate the restore wizard's success on it.
* Restore onto a **new server** loses all per-till roles: every till re-enrols (Management shows "Re-enrol required"; `pos_provision_terminal` is idempotent per `install_id`). Document in `ADR-007` follow-up.
* The `audit_head` outside the dump means a restore of an older `pos_audit_events` leaves a head ahead of the table: `audit_verify` reports it, and the restore flow records "chain rolled back" in the `backup.restored` row. This must be tested.
* `quiesce` before restore: also `pg_terminate_backend` every `pos_t_*` session (provisioner function `pos_fence_all()`) so no till writes mid-restore (R-23 in the discovery doc).

**Test fixtures.**
* `test/data/pg_fixture.dart`: add `PgFixture.provisionRoles()` (as the superuser the suites already use: creates `pos_provisioner`/`pos_enroll` with `roleFor('...')` names — roles are cluster-wide and checkouts share a server — and installs the `pos_sys` functions' owner), plus `PgFixture.tillSession({terminal})` that registers a terminal, creates a `pos_t_` style role with a **checkout-tagged name** and returns an open `PosDatabase`/config for it. The function must accept a role-name prefix parameter in test builds, or the fixture creates the role and mapping itself through a test-only SQL helper (prefer the latter: no production code path takes a role name).
* Default tests continue as superuser (the guard is bypassed because `is_guarded_session()` is false for superusers). **Therefore every guard needs a role-level test; green existing suites prove nothing about E.**
* `grants_cover_usage_test`: (1) tillRepositories must not name `pos_sys.*` tables — assert it; the functions are the interface. (2) Extend `allTables()` regex for `pos_sys.` tables or exclude the schema explicitly, otherwise `CREATE TABLE IF NOT EXISTS pos_sys.x` yields a name `pos_sys` capture of `pos_sys` ... **read the regex `CREATE TABLE IF NOT EXISTS (\w+)`: `\w+` will capture `pos_sys` from `pos_sys.terminal_roles` (it stops at the dot), giving a bogus table called `pos_sys` that no grant mentions; add `pos_sys` handling in the test or the new test will fail for a reason unrelated to security.** (3) A new test `pos_staff_column_grants_test` fails if `pos_staff` gains a column that is not in the step-3 column list.
* `till_grants_test` / `till_grants_enforced_test`: add expectations for the function EXECUTE grants and `USAGE ON SCHEMA pos_sys`.
* New integration suites: `per_till_roles_test`, `terminal_binding_test`, `guarded_writes_test` (one case per row of the E6 table, both with and without a token, with an approval, and with an expired/other-terminal token), `session_token_test` (transaction-local leak test on a pooled connection), `capability_parity_test`, `audit_chain_test`, `enrolment_handshake_test`, `provision_roles_idempotent_test`, `restore_keeps_roles_test` (needs `pg_dump/pg_restore` as existing `pg_archive_restore_test`).

## E10. Risks of building Slice E without PostgreSQL (what **must** run in `scripts/check.sh` before merge)

Everything below is untestable in the planning environment; each is a place a blind implementation will plausibly be wrong.

1. **SQL syntax of the functions/triggers in Dart strings** (`$fn$` quoting, `RETURNS TABLE` name clashes, `SET search_path` with a schema, `SECURITY DEFINER` on `LANGUAGE sql`). Run migrations 54-56 on an empty database **and** on a database that already holds data at migration 53.
2. **PG16 CREATEROLE semantics** (ADMIN OPTION on `pos_till`, creator auto-granted admin on new roles, `GRANT pos_till TO <new>` allowed inside the definer function). Test as a non-superuser definer, on PG16, with a role that really has only `CREATEROLE`. Check PG17 behaviour change (CREATEROLE `createrole_self_grant`) too.
3. **Guard bypass via superuser tests**: all existing suites run as superuser and will stay green while the guard is broken. The role-level suites are the only evidence.
4. **Transaction-local settings over the `postgres` Dart pool**: confirm `set_config(..., true)` in the same transaction as the write on the package's `runTx`, that the pool does not run statements outside it, and that nothing is cached between checkouts.
5. **`session_user` vs `current_user` inside nested SECURITY DEFINER calls** (trigger -> definer function -> definer function).
6. **Capability parity SQL <-> Dart** (E5): silent demotion or silent over-grant. Test enumeration is mandatory.
7. **Cloud seeder and drain on the till role** hitting new guards (e.g. an `UPDATE pos_orders SET server_invoice_number` must still pass; `pos_shifts` upserts from sync; bundle `pos_staff` writes if step 3 changes them). Run `cloud_bootstrap_test`, `outbox_drain_test`, `shift_close_drain_test`, `cloud_refunds_test` as a **mapped role** with a token, not as superuser.
8. **Deadlocks/serialisation**: `audit_head FOR UPDATE` inside transactions that already hold order/shift row locks (lock order orders -> audit head everywhere, or the trigger approach deadlocks under two tills). Needs a two-till concurrency test.
9. **`pg_hba` and TLS interaction** with `hostssl` lines (a till without TLS locks itself out). Windows installer run required (workflow `windows-installer.yml`, manual).
10. **Backup/restore** with `-N pos_sys`, role ownership after `--no-owner`, `pg_dump` run as `pos_backup` (`pg_read_all_data` cannot read `pos_sys` if its grants differ — check), and `pg_archive_restore_test` after the change.
11. **Performance**: the sign-in function plus a token resolve per privileged write (one indexed lookup each); acceptable, but time `submit` of an order with and without guards.
12. **Order of operations in the wizard**: registration is part of `SetupController`; a failure between role creation and storing the password in `SecretStore` leaves a role nobody has the password for. Make `pos_register_terminal` idempotent per `install_id` (re-enrol rotates the password) and test the kill-mid-wizard case (`setup_persistence_test`).

## E11. Files and functions (Slice E)

| File | Change |
|---|---|
| `lib/data/postgres/migrations.dart` | 55 (`pos_sys`, tables, functions, guard triggers in compat mode, `capability_aliases/meta` seed — generated **from** `PosCapability` by a Dart helper so the SQL cannot drift; keep the generator in `lib/data/postgres/capability_seed.dart`), 56 (audit chain), later 57 (step-3 grant narrowing: **not in the same release as 55-56**). |
| `lib/data/postgres/local_bootstrap.dart` | `tillGrants`: schema usage + function EXECUTE; `InstallRole` gains `provisioner`, `enroll`; `roleStatements`; `createRoles` extended; new `provisionPerTillRoles(superuser)`; `ensureTillRole` stays for compat; new `tillGroupLockdown()` list for step 3. |
| `lib/data/postgres/pos_database.dart` | `runTxAs(config, token, approvalId?, action)`; `DeploymentConfig.databaseUser` already per-config. |
| `lib/core/config/deployment.dart` | `databaseUser` set from the terminal-role name; mode logic unchanged. |
| `lib/data/config/terminal_config_store.dart`, `lib/data/config/secret_store.dart` consumers | new key `pos_terminal_role_password`; enrolment writes secret **before** config. |
| `lib/data/postgres/postgres_directory_repositories.dart` | `registerManually`/`connect`/`claimByCode` call `pos_register_terminal`/`pos_auth_params`/`pos_auth_verify`; sign-in returns `DbSession`. |
| `lib/domain/models/shift.dart` (`PosStaff`) | optional `DbSession? session` (opaque token wrapper, `toString` redacted; never serialised to logs — see `network_log.dart` for existing redaction patterns). |
| `lib/data/postgres/postgres_{orders,refunds,shift,cash_movements,business_day,discounts,sync_queue,print_queue}_repository.dart` | `runTx` -> `runTxAs` for the writes in E6. **Mechanical, but each is a money path: one commit per repository.** |
| `lib/domain/services/authorization.dart` | `Approval` carries `approvalId` (DB row), `Authorization.approve` stays for the in-process checks. |
| `lib/features/admin/presentation/supervisor_override.dart` | calls `pos_approve` through the repository (not `byPin`). |
| `lib/features/admin/presentation/management_terminal_pane.dart` | enrolment status, revoke, re-enrol, "enrolment password" display (admin only, shown once). |
| `lib/data/backup/pg_archive.dart`, `backup_service.dart`, `postgres_backup_repository.dart` | `-N pos_sys`, head-hash record, fence, chain verify after restore. |
| `bin/pos_migrate.dart` | `--provision`, `--list-terminal-roles`, `--revoke-terminal`, `--reown`. |
| `installer/provision.ps1`, `installer/xorder-pos.iss` | **Not touched by this task; contract for the installer agent**: call `--provision` after migrate, write `hostssl` lines, `ssl=on`, keep `pos_enroll` password in `install-credentials.json` (add `provisioner`/`enroll` entries; `InstallerCredentials.tryParse` must stay tolerant of unknown keys, it is). |
| `lib/core/l10n/app_strings.dart` | strings: `terminalEnrolled`, `terminalNotEnrolled`, `reEnrolRequired`, `revokeTerminalAction`, `revokeTerminalConfirm`, `terminalRevoked`, `enrolmentPasswordTitle`, `enrolmentPasswordBody`, `roleSetupMissing`, `rolesNeedTechnician`, `sessionExpired`, `signInAgain`, `approvalExpired`, `approvalAlreadyUsed`, `approverMustDiffer`, `writeRefusedByServer`, `auditChainBroken`, `auditChainOk`. |

---

# Recommended implementation order (small commits, each with its acceptance test)

Slice D first; E is independent of D except E5 reuses D's functions.

| # | Commit | Acceptance test (what proves it) |
|---|---|---|
| D-1 | `StaffSecret`, `PasswordRules` (pure Dart) | `staff_secret_test`, `password_rules_test` green with no DB. |
| D-2 | Migration 54 + `tillGrants` EXECUTE + pepper | `scripts/check.sh test/data` : migration applies on empty DB and on a DB at 53; `staff_auth_functions_test` (integration). |
| D-3 | `SessionRepository.signInWithPassword` + Postgres impl + fakes + unconfigured | Repository test against Postgres: right/wrong/locked/unknown/inactive all return the specified sealed value; fake and unconfigured compile (`flutter analyze` clean). |
| D-4 | `StaffAuthPolicy` + mode clamp + settings row | `staff_auth_policy_test` (cloud => `pin`; fallback rule). |
| D-5 | Sign-in screen, set-password interstitial, lockout text; strings EN+AR | Widget tests per policy; existing lock-screen tests unchanged for `pin` policy. |
| D-6 | Admin Mode + `checkStaffSecret` + DB lockout | `admin_entry_test` updated; lockout survives a restart (new integration test). |
| D-7 | Admin `resetPassword`, Staff pane, technician CLI/dialog | `postgres_admin_test` (owner rule), `migration_cli_test` (reset), owner-never-locked-out scenario test (E2E: upgrade DB with PIN-only owner -> PIN in -> prompt -> password works -> policy flip -> PIN no longer unlocks staff but owner can still enter). |
| D-8 | Supervisor override: named approver + persisted lockout | widget test for two-people-same-PIN scenario. |
| D-9 | Idle lock integration with sign-in (coordinate with the in-flight work); **quick unlock only if decision #1 says so** | fake-clock widget test: 5 min idle -> lock; interaction resets; no lock mid-payment. |
| E-1 | `pos_sys` schema + mapping + `pos_terminal_id()` + compat guard on `terminal_id` (migration 55 part 1) | `terminal_binding_test` with a real mapped role (writes with another terminal id refused; unmapped group member refused; legacy `pos_till` and superuser pass). |
| E-2 | Provisioning: `pos_provisioner`, `pos_enroll`, `pos_register_terminal`, `pos_revoke_terminal`, `pos_rotate_my_password`; `pos_migrate --provision` | `per_till_roles_test`, `enrolment_handshake_test` as a non-superuser definer on PG16; revoked role cannot connect. |
| E-3 | App enrolment: wizard calls the function, stores secret, reconnects as `pos_t_*` (main + child + pairing code) | `setup_persistence_test` extension (kill mid-wizard resumes), `postgres_wiring_test`. |
| E-4 | Sessions: `pos_sign_in`, `staff_has`, capability seed generator, parity test | `capability_parity_test` for `PosCapability.all` x `SystemRoles`; token wrong-terminal/expired refused. |
| E-5 | `runTxAs` + audit insert guard (actor/terminal forced) | `session_token_test` (no leak across pooled txs), audit forged-actor refused. |
| E-6..E-12 | One commit per guarded act: void -> refund -> discount -> cash movement -> shift/day close -> price override -> held-row release | For each: a role-level test with the 4 cases (no token refused / token without cap refused / with cap ok / with approval ok), and the existing repository suite unchanged green. Refund and price override are last: highest uncertainty. |
| E-13 | Approvals (`pos_approve`, `pos_sys.approvals`) + supervisor dialog | single-use, expiry, self-approval, critical-capability refusals. |
| E-14 | Audit hash chain (migration 56) + backup head record + restore verify | `audit_chain_test`, `backup_restore_test` extended. |
| E-15 | Backup/restore with `-N pos_sys`, fence | `pg_archive_restore_test`, `restore_keeps_roles_test`. |
| E-16 | Management terminal pane (status/revoke/re-enrol) | widget test + integration. |
| E-17 (release N+2, separate) | Step 3 lockdown migration 57 (`pos_till` NOLOGIN, column-scoped grants, hash columns unreadable), cloud seeder via `pos_seed_staff` | `till_grants_enforced_test` rewritten for the new surface; `pos_staff_column_grants_test`; direct `psql` as a till role: every row of the E6 table refused. |

Gate before **any** E merge: `scripts/check.sh` fully green on PostgreSQL 16, plus the manual Windows installer run for any commit touching `installer/` or `pg_hba`.

---

# Decisions needed from the product owner

1. **Idle-lock unlock (D6):** after 5 minutes idle, does the same person unlock with (a) password only, (b) a 4-digit PIN they set (quick unlock), or (c) PIN within the shift, password for a different person / after N hours? Recommendation (c). Also the absolute session length (8 h / 12 h / shift end).
2. **PIN's remaining jobs (D7):** keep the PIN for supervisor approvals and quick unlock, and require password for Admin Mode and forced terminal reset? Or retire the PIN entirely offline (then approvals need a password too)?
3. **Cloud (D8):** approve raising the backend contract (dashboard-set password, bundle `staff[].password`) now, and confirm dashboard-only management of cloud passwords for v1 (no till-side change upstream).
4. **Password policy numbers (D4, Q18):** minimum length (8 or 10), lockout threshold/duration (5 tries, 30 s doubling to 15 min proposed), whether a per-username lockout (can lock the owner out for up to 15 min) is acceptable.
5. **Cloud staff writes (E6):** accept moving the cloud seeder to a `SECURITY DEFINER` function and revoking `pos_staff` writes from cloud tills (closes "stolen till credential repoints a row at the owner").
6. **`pos_admin` network reach (E8):** loopback only (Management only on the main device) or still LAN-reachable from children.
7. **Name tiles on the sign-in screen:** keep the roster visible (speed) or hide it behind typing the username (less disclosure).
8. **Enrolment credential for new tills:** one shared "enrolment password" shown on the main device, or a one-time pairing code per new till (more secure, one more step). Also whether a technician or any `terminal.manage` manager may enrol a till.
9. **Grace period for existing accounts:** how long "Set your password later" may be postponed in `pinOrPassword`, and who flips to `password` (owner in Management, or technician only).
10. **Step-3 timing:** is "shared `pos_till` login disabled" acceptable in the release after step 2, given that any till not yet re-enrolled stops working? (Owner needs a visible "N of M tills enrolled" before the technician flips it.)
11. **Audit chain:** acceptance of the per-restaurant serialisation cost, and whether an off-box anchor (e.g., head hash in the day-close printout or email) is wanted.

# Verified-by-reading facts vs assumptions

**Verified by reading (code/docs in this repository, not executed):** the `pos_staff` shape and PIN storage; `PinHash` parameters and the exactly-4-digit rule; lock screen already uses username + PIN with no lockout; Admin Mode lockout is in-memory; supervisor override resolves approver by PIN alone; the three installed roles and their attributes; `tillGrants`/`administrativeGrants` contents and the offline REVOKE of `pos_staff` writes; Management writes run on the admin connection; `terminal_id` is client-supplied and exists on the listed tables; migration 53 is last; refund triggers and the one-owner trigger already use `SECURITY DEFINER` with pinned `search_path`; the restore command line (`--clean --if-exists --no-owner --single-transaction`); cloud bundle carries `staff[].pin` only and POS-BE-024 fixes PIN at 4 digits and says the PIN is never accepted by dashboard login; the seeder upserts `pin_salt/pin_hash`; child registration uses the shared `pos_till` password plus a manager's username+PIN; `grants_cover_usage_test` greps source files for table names; `check.sh` runs as a superuser; the installer ships PostgreSQL 16; `router.dart` already references `LockReason.inactivity`.

**Assumptions (flag every one when implementing):**
* PostgreSQL 16 CREATEROLE/ADMIN OPTION behaviour and `pg_dump/pg_restore --exclude-schema` availability; server >= 13 for `gen_random_uuid()` and built-in `sha256()`.
* Pure-Dart PBKDF2 at 600 000 iterations is acceptably fast (0.3-0.6 s) on the slowest till; isolate use is sufficient.
* TLS-by-default lands before the password path is relied on (K is password-equivalent on the wire).
* `pos_settings` can hold `staff_auth_policy` as a string with the existing naming conventions.
* The order-line schema has (or can get) a flag distinguishing a price override; the discount cap can be validated at `pos_orders`/line insert (not read in detail).
* `pos_backups`, `pos_cloud_state`, `pos_outbox` do not need terminal binding / are not guarded; drain, seeder and backup writes stay compatible with the guard triggers.
* The pairing-code claim path can call the same role-creation function; ADR-008 will make the platform the staff authority in cloud.
* No Unicode normalisation is needed for passwords across Windows and macOS keyboards (to be tested with Arabic).
* The in-flight idle-lock work can be reconciled with D-9; its current state was not inspected beyond the `router.dart` reference.

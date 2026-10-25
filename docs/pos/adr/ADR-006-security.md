# ADR-006 — Identity, permissions, secrets, LAN security

**Status:** Accepted business rule, with pending protocol details. Technical design: Proposed.
**Source:** case report ADR-006; evidence `discovery/SECURITY_AND_RECOVERY.md` §3–§7, §15.

## Context

Cashiers sign in with a 4-digit PIN; permissions are enforced in Dart; every till shares one database
credential; secrets sit in a plaintext JSON file; LAN traffic is plaintext by the supported install.

## Decision (accepted rules)

- Employees authenticate with **username + password, once per session**.
- **Auto-lock after 5 minutes idle.**
- Sensitive DB/cloud credentials use **Windows DPAPI or macOS Keychain** (OS secure storage).
- LAN TLS is **enabled by default but optional**; disabling requires explicit advanced technician
  action (safe proposal to confirm).
- **Technician-only actions must be enforced beyond hiding UI.**

## Current code `[CODE]`

| Fact | Evidence |
|---|---|
| `secrets.json` holds `pos_till`, `pos_backup`, **`pos_admin`** passwords and the cloud device token in plaintext; `chmod 600` on POSIX, **nothing on Windows**; no keystore package in `pubspec.yaml`; comments claim otherwise | `file_secret_store.dart:113-190`, `providers.dart:3055-3078`; §14 |
| PIN: PBKDF2-HMAC-SHA256, 120k iterations, 16-byte salt, 4 digits; `pos_till` has SELECT on `pos_staff` hashes → offline-crackable | `pin_hash.dart:25,38-74`, `postgres_directory_repositories.dart:425-470` |
| **Cashier lock screen has no lockout**; Admin Mode lockout is in-memory, per terminal | `lock_screen.dart:51-75`, `admin_session.dart:205-232` |
| **No cashier idle auto-lock** (Admin Mode only) | `admin_session.dart:245-260`; grep `idleTimeout|autoLock` |
| **Permissions enforced in Dart only**; `discount.apply`, `price.override`, `payment.remove`, `day.close` are UI gates only; `Approval` is "not a cryptographic token" | `authorization.dart:62-70`; §7.3 |
| **One shared `pos_till` role**; `terminal_id` and `staff_id` are caller-supplied | `deployment.dart:211`, `providers.dart:2178-2201` |
| Cloud till role can write `pos_staff` and the catalogue (seeder grants) | `local_bootstrap.dart:876-925` |
| Installer never sets `ssl=on`; `host` not `hostssl`; client uses `SslMode.disable` on loopback or trusted private host | `provision.ps1:158-168`, `pos_database.dart:293-295`, `deployment.dart:350-351` |
| Refund counters already move only via a `SECURITY DEFINER` trigger with pinned `search_path` — the pattern exists | `migrations.dart:1231-1305` |
| Audit log append-only by grant + trigger, but the owner can drop the trigger; restore replaces the table; **no hash chain** | `migrations.dart:519-535`; R-05 |
| No crash handler, log file, telemetry or support bundle | §12.9 |

### Implemented since: secrets to the OS store (Phase 1, slice B)

The first row above describes the code before this slice. Now:

- `SecretStore.forPlatform()` (`lib/data/config/secret_store.dart`) is the only place a store is
  chosen. Windows gets `WindowsDpapiSecretStore`: `CryptProtectData` in current-user scope,
  `CRYPTPROTECT_UI_FORBIDDEN`, per-key entropy, ciphertext in `secrets.dpapi`. macOS gets
  `MacKeychainSecretStore`: Security.framework via `dart:ffi`, generic-password items under the
  service `io.xorder.pos`. Any other platform gets `DevelopmentFileSecretStore`, the old plaintext
  file, named for what it is. Nothing falls back. A store that fails throws
  `SecretStoreUnavailable`, and the setup wizard's existing `keystoreUnavailable` warning reports it.
- `LegacySecretMigration` moves an existing `secrets.json` into the OS store at first launch:
  write all, verify all, then zero and delete. Any failure rolls back what it wrote and leaves
  the file untouched.
- **Not done here:** `pos_admin` is still persisted, now in the OS store rather than the file.
  Whether to persist it at all is still Q17. "`pos_admin` password not present on any till
  disk" therefore still fails as an acceptance test. Neither native store has been run on its
  OS yet: `test/data/os_secret_store_platform_test.dart` must pass on a Windows till and on a
  Mac.
- **Known cost on macOS:** an ad-hoc or unsigned build is a different app to the keychain after
  every rebuild, so the 2026-09-04 prompt returns for those builds.

## Gaps

- **Per-user authentication is meaningless while permissions are Dart-only and all tills share one
  DB credential** (reviewer correction). Username+password at the lock screen does not change what a
  `psql` session with the till password can do.
- **"Technician-only restore" cannot be enforced while the `pos_admin` password is in
  `secrets.json`** on any till that has opened Management.
- TLS default off; no silent-downgrade guard.
- Audit-log tamper evidence and field diagnostics: **open items** (see below).

## Proposed design (not yet approved)

- **Secrets → OS store** (DPAPI via `win32`/`ffi`; Keychain on macOS), replacing `FileSecretStore`;
  vault unavailable → fail safe (refuse to sell), **never plaintext JSON**. Remove `pos_admin` from
  persisted secrets; technician types it for restore/reset.
- **TLS on by default:** installer generates a self-signed cert, writes `ssl=on` + `hostssl`; POS
  defaults to `verifyFull` (cert pinned at pairing) or `require`; downgrade only via an audited
  technician toggle with a persistent warning. Never downgrade silently on handshake failure.
- **Per-till DB roles** `pos_till_<install_id>` created at registration (ADR-005 seat flow), each a
  member of a `pos_till` group role; `terminal_id` derived from `current_user` inside DB functions;
  revocation = `ALTER ROLE … NOLOGIN`.
- **DB-side enforcement for privileged writes:** void, refund, discount above limit, price override,
  payment removal, shift close for another's drawer, terminal reset, held-row release — each a
  `SECURITY DEFINER` function that verifies the acting staff's session token (issued at sign-in,
  stored in a `pos_sessions` table) and permissions from `pos_roles`, then writes the audit row. The
  till role loses direct UPDATE on those columns.
- **Staff username + password:** PBKDF2 reuse with a longer secret; one sign-in per session; 5-minute
  idle lock (`lock_screen.dart`); lockout after N failures persisted in DB (not memory); no user
  enumeration. Migration path: existing PIN accounts prompted to set a password; owner never locked out.
- **Open items to carry in this ADR:** audit-log tamper evidence (hash chain per restaurant, optional
  external anchor; restore re-verifies the chain) and **diagnostics** (crash handler, rotating local log
  with redaction, support bundle export without credentials; no cloud telemetry in offline plan).

## Acceptance tests

- Offline password verification; session expiry; idle 5 min → lock; lockout persisted across restart.
- Access tests for **every** privileged write/read/export from a direct DB session with a till role.
- Credential rotation; OS-store tests on Windows and macOS; vault-unavailable path.
- TLS downgrade test: handshake failure is an error, not a plaintext retry; override is audited.
- Password reset and recovery without locking out the owner.
- `pos_admin` password not present on any till disk after setup.

## Open questions

- GAPS §5 **Q13** (per-till credential — accepted here), **Q17** (OS store — accepted; persist admin
  password at all? proposal: no), **Q18** (password complexity/lockout numbers; idle 5 min accepted),
  **Q19** (TLS default — accepted on), **Q20** (diagnostics/privacy limits).
- Case report: session scope across shifts; role-based manager override; TLS-off exception recording;
  whether TLS-off is allowed on any LAN (P2); staff identities local vs central in Cloud plan (ADR-002).

## Related roadmap phase

**Phase 1.** See [`../20-implementation-roadmap.md`](../20-implementation-roadmap.md).

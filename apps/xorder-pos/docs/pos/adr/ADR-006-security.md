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
| Installer never sets `ssl=on`; `host` not `hostssl`; client uses `SslMode.disable` on loopback or trusted private host — **superseded by slice C below** | `provision.ps1:158-168`, `pos_database.dart:293-295`, `deployment.dart:350-351` |
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

## Slice C design — LAN TLS (2026-10-25)

Accepted rule: TLS on by default, off only by an explicit technician action, **never** a silent
downgrade on handshake failure. Nothing here was run: no Windows, Flutter or PostgreSQL in the
sandbox that wrote it.

**Server certificate (installer, `lan` task).** The bundle is EDB's binaries-only zip; whether its
`pgsql\bin` carries `openssl.exe` could not be confirmed, and one that does needs an `openssl.cnf`
the zip does not ship. So `provision.ps1` makes the certificate with .NET's `CertificateRequest`
(Framework 4.7.2+, on every serviced Windows 10), in memory, with an ephemeral CNG key created
`AllowPlaintextExport` and exported as PKCS#8. Rejected: `New-SelfSignedCertificate` (leaves the key
in the machine store). Shape: self-signed RSA-2048/SHA-256, `CA:TRUE pathlen:0` + `keyCertSign` (so
it can be its own trust anchor, the shape PostgreSQL's docs use for `verify-full`), EKU
`serverAuth`, SAN = computer name, `<name>.local`, FQDN, `localhost`, `127.0.0.1` and every current
RFC 1918 IPv4. **825 days** — Apple's TLS ceiling, and a child may be an iPad. Idempotent: an existing
pair is kept unless missing, unreadable or inside its last 60 days (renewal = every till re-pairs;
the installer says so, exit 3).

**Files.** `server.crt`/`server.key` in the data directory (Administrators, SYSTEM, NetworkService).
The key file is created empty, `icacls /inheritance:r` to Administrators + SYSTEM full and
NetworkService read, *then* written; re-asserted every run (PostgreSQL on Windows checks no key
permissions itself). A public copy goes to `%ProgramData%\XOrder POS\server-certificate.pem` for the
Management pane. Key material is never printed; the log gets the fingerprint and expiry only.
`postgresql.conf` managed block: `ssl = on`, `ssl_cert_file = 'server.crt'`, `ssl_key_file =
'server.key'`, `ssl_min_protocol_version = 'TLSv1.2'`. `pg_hba.conf` managed block: **`hostssl`**
for 10/8, 172.16/12, 192.168/16 (initdb's loopback lines untouched). No certificate → LAN not
opened at all (listen localhost, no firewall rule, exit 2), never opened plaintext.

**Server-side override.** `provision.ps1 -Lan -LanTls Off` (elevated prompt, technician only, never
the installer UI) writes those lines as `host` — encrypted still accepted, plaintext too — and
records who/when in a marker inside the data directory (ProgramData lets any user create files);
`-LanTls On` removes it. An **upgrade of a pre-slice-C LAN install** carries the old answer over
(exit 4): every existing child was set up plaintext, and a child that cannot reach its database
cannot open Management to pair, so `hostssl` on upgrade would strand them all at once.

**Child trust: fingerprint pinning, confirmed by a person.** `postgres` 3.5.12 (source read) has no
certificate callback and does not expose the peer certificate: `verifyFull` throws
`BadCertificateException(cert)`, `require` accepts *everything*. So a pin is a
`SecurityContext(withTrustedRoots: false)` whose only anchor is the paired certificate, with
`verifyFull` (`lib/data/postgres/pos_tls.dart`). Flow: no pin → verified chain → a self-signed server
refuses → the wizard's connection step asks the server for its certificate (SSLRequest + a TLS
handshake it refuses; nothing else is sent) → shows the SHA-256 (`AB:CD:…`, mono, LTR) → the
technician compares it with Management › Devices on the main device and presses *The fingerprints
match* → `config.json` stores `pinned_certificate_sha256` **and** `pinned_certificate_pem` (the
driver can trust a certificate, not a hash) → reconnect. Both halves are cross-checked before every
pool opens. A changed address clears the pin. A CA-issued server needs no pin (verified chain).

**Decision (pure, `LanTls.decide`).** loopback → plaintext; pin → pinned; `allow_insecure_lan` on a
private address → plaintext; else verified chain. Pin beats the flag. `verify_tls: false` from an
old `config.json` reads as `allow_insecure_lan: true` (it *was* plaintext), with the warning on.

**Client override.** Only in Management › Devices, behind `terminal.manage`; the audit row
(`terminal.lan_encryption_changed`, before/after transport + fingerprint) is written first and a
refused row means no change. It clears the pin; turning encryption back on is a pairing. While on,
the start screen and the pane show a warning. The wizard has no plaintext option at all — the
pre-slice-C "trust without a certificate" tick is gone.

**Failure.** Every TLS failure is `PosDbFailure.tls` (by type for `BadCertificateException`, by text
for "does not support SSL" / `no encryption`). The pool is not rebuilt in the clear; the start
screen says the till could not confirm whose server it reached; the wizard says which of untrusted /
changed / name mismatch / not offered it was. `LocalBootstrap`'s maintenance connection, which used
`require`, now uses the same rule.

**To verify on real machines:** that `setTrustedCertificatesBytes` makes the pin the only anchor on
Windows and macOS; that a self-signed `CA:TRUE` leaf verifies as its own anchor; that IP SANs are
checked when the till dialled an IP; the PowerShell under 5.1 on a clean Windows 10.
`test/data/lan_tls_handshake_test.dart` checks the first three on whatever machine runs it.

**Not in this slice:** re-pairing from the start screen (a child whose server certificate changed
cannot reach Management — same gap as a changed till password today); `pg_dump`/`pg_restore` over a
pinned LAN connection (they get `PGSSLMODE=verify-full` and no root file, so they fail closed);
`pos_migrate --no-verify-tls` stays its LAN spelling and cannot pin.

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

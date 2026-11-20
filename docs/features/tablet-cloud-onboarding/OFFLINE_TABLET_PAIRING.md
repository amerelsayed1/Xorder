# Offline tablet pairing — design proposal (Stage 7, Q3 and Q6)

Status: **proposal, revised after an independent security review (section 8), not built, not approved** · 2026-11-19 · tablet-cloud-onboarding
Needs: the owner's decisions in section 6, then a second review of the revised design, before any code.

## 1. What the owner asked for
- Q3: the tablet may run the **Offline** app. It can only be a **child** of a desktop main till (a tablet cannot host PostgreSQL).
- Q6: the offline tablet gets **its own short form**: the main till's address, a staff username and that person's PIN; branch and terminal taken from the main till.

## 2. What exists today (verified in source)
| Fact | Where |
|---|---|
| A child connects **straight to the main device's PostgreSQL** and cannot leave the connection step without a **database password**, a TLS-pinned address and a licence that lets it sell | `packages/shared_module/lib/features/setup/domain/setup_state.dart:488-492` |
| The main till already serves a **TLS link to waiter handhelds** with a certificate it mints; a handheld **pins its SHA-256** after the waiter confirms it once on screen | `lib/features/waiter_link/waiter_link_tls.dart:1-30`, `packages/xorder_waiter_link/` |
| The database role a till uses is one shared `pos_till` role. The administrator credential the main till keeps (`pos_admin`) is **`LOGIN CREATEDB` only: no superuser, no CREATEROLE**, and `ensureTillRole` refuses (`TillRoleRefused`) when asked to create a role without it. **The first draft of this design assumed the opposite; the review caught it** | `lib/data/postgres/local_bootstrap.dart:235-251, 296-312, 1265` |
| On Android there is no installer marker, and **absent reads as main device** | `lib/data/config/installed_role.dart` (fixed in this stage: Android now reads as child) |

So the short form has **nothing to authenticate a database connection with**: address + username + PIN is a staff identity, not a database credential. Something on the main till must hand the tablet a credential, and the tablet must be sure it is talking to the right main till. That is a **new LAN contract and a security design**, not a UI change.

## 3. Proposed handshake
1. On the main till, Settings › Devices › **Add a tablet** shows a one-time **pairing code** (16 characters, Crockford base32, 80 bits), valid 5 minutes, one use, and starts listening on the existing LAN link.
2. On the tablet the person types: the till's address (or picks it from a LAN scan), the pairing code, then their staff username and PIN.
3. The tablet connects over TLS **without trusting the certificate yet** and reads its SHA-256 `F`.
4. **The till sends a fresh `nonce_till` first.** The tablet sends `proof = HMAC-SHA256(k_proof, nonce_tablet ‖ nonce_till ‖ F ‖ till_id ‖ "pair-v1")`, where `k_proof` and the encryption key are two HKDF outputs of the code with distinct `info` labels. The main till recomputes it with **the fingerprint it actually presents**, comparing in constant time; the tablet does the same for the till's reply. A man in the middle presents a different certificate, so the proof fails, and the code is never sent. A recorded proof cannot be replayed, because the till's nonce differs each time.
5. On success the main till creates a **per-device PostgreSQL role** and returns its password, the **database server's own certificate fingerprint**, the branch and the terminal id, **encrypted with an AEAD (AES-GCM or ChaCha20-Poly1305) under a key derived with HKDF from the code and both nonces, with the transcript hash as associated data**. The tablet trusts the till only once that decryption verifies. The role is made **without granting `pos_admin` CREATEROLE**: at install a superuser creates a `SECURITY DEFINER` function that only `pos_admin` may run; it takes an integer device id, builds `pos_dev_<int>` itself with `format('%I')`, generates the password on the server and runs `CREATE ROLE … LOGIN IN ROLE pos_till` (inheriting `pos_till`'s grants, so later migrations' grants apply automatically). A matching revoke function does `ALTER ROLE … NOLOGIN`, `pg_terminate_backend`, then drops the role.
6. The tablet stores the password in the Android Keystore (Stage 1), pins both fingerprints, then signs the person in locally (username and PIN against the main till's staff table). The pairing code is spent; a second use fails.
7. Revoking a tablet drops its role on the main till (Settings › Devices), which closes that tablet's access at the database.

## 4. Why these choices
- **Not the shared `pos_till` password:** one leaked tablet would mean rotating every till's password. A role per device can be revoked alone.
- **An 80-bit code, not 8 digits:** the proof is a hash of the code. A short code can be brute-forced offline from a captured exchange. A short human-typed code would need a PAKE (SPAKE2 or OPAQUE), which is a library and more review. A longer code needs no new primitive, at the cost of typing 16 characters once. A QR code scanned by the tablet would avoid the typing but adds a camera permission and a scanner dependency. The review confirmed 80 bits is adequate against offline guessing, so the lock-out protects availability, not secrecy.
- **Reuse of the pinned-TLS pattern** (the waiter link, ADR-006): no new trust model.

## 5. Risks and unknowns (to be settled by the review)
- The main till holds the PostgreSQL **administrator** credential to create roles. The handshake endpoint therefore sits in front of a powerful action: rate limits, a lock-out after a few bad proofs, and the code dying on the first failure are needed.
- A cloud main till (SQLite, no PostgreSQL) cannot host this at all; the offline tablet pairs only to an **offline desktop main**.
- Whether the licence's terminal limit is checked on the main till at pairing (a child "is one more of the licence's terminals", `setup_controller.dart`, `registerTerminal`).
- Clock skew, a main till that is off, a changed IP address (the tablet should re-find it by name or scan), and a tablet that is lost (revocation).
- The existing database TLS fingerprint and the waiter-link fingerprint are two different certificates; the design must deliver both.
- **UNVERIFIED:** which call the waiter link already exposes that the short form could reuse, and whether its server can host a second, unauthenticated-until-proof route safely.

## 6. Decisions needed from the owner
1. **Code form:** 16 typed characters (recommended), a QR scan, or accept a short code with a PAKE?
2. **Credential:** a role per tablet (recommended) or the shared `pos_till` password?
3. **Interim:** until this is built, should the offline tablet use today's child path (type the database password), which already works once the app is installed on Android, or wait?
4. **Scope:** build it in this feature, or as its own feature (`offline-tablet-pairing`)? The change touches the main till's database administration, a new LAN route and the Settings › Devices screen.

## 7. If approved, the staged build
1. Pairing core in `packages/xorder_waiter_link` or a sibling package (pure Dart, unit-tested: code, proof, sealing, expiry, single use, lock-out).
2. Main till: the Add-a-tablet screen, the role create/drop with the administrator credential, revocation.
3. Tablet: the short form (address, code, username, PIN), Keystore storage, pinned fingerprints.
4. Tests: wrong code, replayed code, expired code, a different certificate (MITM), revoked tablet, licence limit; an on-device run against a real main till.
5. An independent security review (`security-reviewer`) of the design **before** step 1, and of the code before release.

## 8. Independent security review — findings and what changed (2026-11-19)
A read-only `security-reviewer` read this design against the real code. Its two load-bearing claims were **re-checked by me in source**: `pos_admin` has no CREATEROLE (`local_bootstrap.dart:301-302`), and the waiter link reads a request body with `utf8.decodeStream` and no size cap (`packages/xorder_waiter_link/lib/src/server.dart:305`). The rest is the reviewer's reading, **not verified by me**.

| # | Severity | Finding | Change made or required |
|---|---|---|---|
| 1 | High | The stored admin credential cannot create roles; granting CREATEROLE to a credential kept in the till's OS store is a privilege escalation | Section 3 step 5 now uses a `SECURITY DEFINER` function run by `pos_admin`, taking an integer id. **Open:** whether the Windows installer can create it (not verified) |
| 2 | High | Copying `pos_till`'s column-scoped grants per device would silently lack grants added by later migrations | `CREATE ROLE … IN ROLE pos_till` (inherit) |
| 3 | High | A new pre-auth LAN route has no body limit; the existing lock-out is per-IP, in memory, unbounded | Required in the build: ~2 KB body cap, a global attempt budget, a cap on concurrent pairing connections, and a listener open **only while the pairing window is open**. Do not reuse the existing lock-out |
| 4 | Medium | The proof had no till nonce (a recorded proof could be replayed inside the 5-minute window); "code dies on first failure" lets any LAN host cancel every pairing | Till nonce added; HKDF with separate labels; AEAD with transcript as associated data; constant-time comparison; the code dies after about 5 bad proofs per attempt, not per IP |
| 5 | Medium | Role-name injection | Not an issue when the name is `pos_dev_<int>` built on the server (the identifier rule is `^[A-Za-z_][A-Za-z0-9_]*$`); never derive it from a tablet-supplied name (63-character truncation) |
| 6 | Medium | Revocation: `DROP ROLE` fails with live sessions; a lost tablet holds a direct database credential that the staff PIN does not protect | Terminate-then-drop (or `NOLOGIN` first); Devices list with last-seen and "revoke all"; re-pairing rotates the role password; the tablet wipes its stored password and pins when refused |
| 7 | Low | The waiter-link certificate is regenerated after 825 days; its fingerprint changes and every pin breaks | A re-pair flow, or re-pinning signed by the old key |
| 8 | Low | Expiry on the main till's clock only; used-code and nonce state must not survive a restart as valid; licence terminal limit must be checked | Required in the build |

Not verified by the review or by me: the Windows installer's ability to create the function, `pg_hba` and `max_connections` on installed machines, whether Dart's TLS exposes a channel-binding exporter (the fingerprint binding is the practical choice), and the whole of `waiter_link_host.dart`. A **second review of the revised design** is needed before any code.

# Technician reset by a signed XOrder code — pos-technician-reset-code

Status: **proposed** · 2026-10-27 · Source: the owner, this session: "update this to be super admin password it should be: tech for user name, password: 2050", then "this should be username and password for Technician only for xorder ? so ?", then `/develop-feature` on the signed-code proposal that followed · Verified against: xorder-pos `5cf13cc` + uncommitted work (not this feature's), xorder-cloud `775bf0f` + uncommitted work (not this feature's)

> **Read this first.** The owner asked for a credential that **only XOrder's technician** holds. A fixed `tech` / `2050` baked into the app was **advised against** (it would be one key to every till, in every copy of the app) and not adopted. This description is the signed-code design proposed instead. The owner ran `/develop-feature` on it but has not yet answered the open questions in section 13; every "recommend" there is mine, not a decision.

## 1. Summary
Clearing somebody's Admin Mode password (including the owner's) at a till today needs the **restaurant's PostgreSQL administrator password**, a secret held by whoever installed the machine. This feature replaces that with a **short-lived code issued by an XOrder technician** from the Super Admin panel. The till verifies the code offline, against XOrder's signing key, for that one till, that one restaurant and that one username. The restaurant never needs, or learns, the database password.

## 2. Why
- **Who is hurt:** an owner who forgot their Admin Mode password and has no technician on site (a café or food-truck owner who installed it alone); and the opposite case, a manager or installer who knows the database password and can reset the **owner's** back-office access without XOrder.
- **When:** the "forgot password" moment, which is also when the person is least able to find a PostgreSQL password.
- **Evidence:** on 2026-10-27 the owner met the dialog (screenshot) and could not tell what to enter; its empty-field error ("no active person with this name has a password to clear") is misleading (`admin_session.dart:659-661`).
- **Venue models:** café and food truck (one person, offline, no IT) benefit most; restaurant (technician-installed) benefits from audit; cloud kitchen: same flow, no table assumptions.

## 3. Goal and success
Only an XOrder technician can authorise a reset; the restaurant needs nothing but the code; a leaked code is useless on any other till, for any other person, or after about 15 minutes; every reset names the technician in the till's audit log and in the cloud's.

## 4. Users, roles and permissions
| Who | What | Identifier |
|---|---|---|
| XOrder technician (cloud platform user) | Issues a reset code in the Super Admin panel | **New platform capability** (name to settle, e.g. `pos_reset_codes.issue`). Today `licences.manage` is `SUPER_ADMIN` only (`routes/api.php:160-171`) and `SUPPORT` holds only `restaurants.view`, `audit.view`, `insights.view` (`RoleEnum.php:84-88`), so a technician cannot do this today. **Granting it to `SUPPORT` widens a role: needs the owner's approval.** |
| Person at the till | Types the username and the code in the technician reset dialog (reached before signing in) | none; unchanged (`admin_sign_in.dart:399-412`) |
| The person being reset | Opens Admin Mode once with their PIN and chooses a new password | existing (`admin.enter`) |

## 5. Today (verified in source)
| Fact | Where |
|---|---|
| The dialog asks for a username and "the back-office database password" and offers it behind a "Forgot password? Technician reset" link. | `apps/xorder-pos/lib/features/admin/presentation/admin_sign_in.dart:399-412`, `:425-520` |
| The logic: a per-terminal attempt limiter, then a probe of the typed password against PostgreSQL, then `UPDATE pos_staff SET password_hash = NULL, password_set_at = NULL` for the active person with that username who has a password; audit `staff.password_cleared` with the generic actor `technician`. | `lib/features/admin/application/admin_session.dart:649-686`; `lib/app/providers.dart:2739-2752`; `lib/data/postgres/postgres_admin_repositories.dart:979-1018`; `lib/domain/repositories/admin_repositories.dart:439-443` |
| An **empty** password or an empty username returns the "nobody" outcome, the same text as "no such person". | `admin_session.dart:659-661` |
| The ADR also describes a command-line reset (`dart bin/pos_migrate.dart --reset-staff-password <username>`) for a technician at the machine; accepted trade-off: the lockout cap and "technician clear exists". | `docs/pos/adr/ADR-006b-staff-auth-and-db-roles-design.md:136`, `:223` (whether the command is built: **UNVERIFIED**) |
| The cloud already signs things with Ed25519: `LicenceIssuer::mint` signs each licence with `LICENCE_SIGNING_KEY` (`sodium_crypto_sign_detached`). | `apps/xorder-cloud/apps/api/app/Services/LicenceIssuer.php:294-302`, `:497-499` |
| The till verifies licences offline with a public key shipped in the binary, with key-id checks; its own comment says the check is "commercial hygiene, not security": **anyone willing to patch the binary defeats it**. | `apps/xorder-pos/lib/features/licensing/data/license_keys.dart:14-18`; `domain/license_verifier.dart:78-` |
| A till has an identifier used for licence pinning (`TerminalIdFingerprint`; derivation **UNVERIFIED**). | `lib/features/licensing/data/file_license_store.dart:78` |
| There is **no** cloud endpoint, panel page or code format for reset codes, and no per-person technician identity in the till's audit (the actor is the literal `technician`). | grep of both repos |
| Existing tests of the current reset: `test/features/admin_session_test.dart`, `management_gate_test.dart`, `test/support/fakes.dart`. | `apps/xorder-pos/test/` |
| No inventory row or feature folder covers the technician reset (documentation gap). | `docs/FEATURE_INVENTORY.md`, UNVERIFIED by grep |

## 6. Scope
**In**
- A cloud action for a permitted platform user to issue a reset code for (restaurant, till, username), shown once, expiring, audited.
- A POS verification of that code and the reset it authorises, in the existing technician reset dialog, offline.
- Clear dialog wording and error messages in Arabic and English, including the fix of the empty-field message.
- Audit that names the technician, in the till and in the cloud.

**Out**
- Resetting a **PIN**, changing roles, or any access other than clearing one person's Admin Mode password.
- Any fixed or shared credential (`tech` / `2050` or similar).
- Changing the licence signing, activation or renewal flows.
- The wizard's database-administrator step (`pos-setup-owner-step`).
- Remote control of the till, or any till-to-cloud call at reset time (the till stays offline-capable).

## 7. Behavior and business rules
- **BR-1 XOrder only.** A code can be issued only by a signed-in platform user holding the new capability, through the cloud; the till accepts only a code whose signature verifies against XOrder's published key.
- **BR-2 What a code says (signed payload, versioned).** Purpose `staff_password_reset`; the restaurant (tenant slug); the till; the target username; issued-at and expires-at (**about 15 minutes**); a single-use id; the key id; the issuing technician's id and name. Format and key handling are specified in the plan, not invented here.
- **BR-3 What the till checks, all of them.** Signature and key id; purpose; restaurant equals this till's restaurant; till equals this till; username equals the one typed; not expired; not already used. Any failure refuses with its own plain sentence and changes nothing.
- **BR-4 Effect.** Identical to today's: the active person with that username who has an Admin Mode password has it cleared; their PIN and everything else are untouched; they set a new password at their next Admin Mode entry. No database administrator password is asked or used in this flow.
- **BR-5 Audit.** The till writes `staff.password_cleared` with the technician's name and id from the code (replacing the generic `technician`); the cloud records who issued which code for which restaurant, till and username, and when. **Never** the code itself in plain text in either log.
- **BR-6 Limits.** The existing per-terminal attempt limiter and lockout apply to wrong codes. The cloud rate-limits issuance per technician.
- **BR-7 Dialog.** Two fields: Username, and the reset code from XOrder support; one plain explanation ("contact XOrder support; they will give you a code for this till"); the till's identifier shown so it can be read to the technician. The database password field and its wording are gone from this dialog (decision **Q3**).
- **BR-8 One use.** A code works once, even inside its 15 minutes, even if it was typed wrong after the first success (**Q5** for how this is stored offline).
- **BR-9 Leaving the company.** Disabling the technician's cloud account stops them issuing new codes; codes already issued expire on their own.

## 8. Acceptance criteria
- **AC-1** Given a platform user without the capability, when they request a reset code, then the cloud refuses (403) and issues nothing. *Cloud feature test.*
- **AC-2** Given a technician with the capability, when they request a code for a restaurant, a till and a username, then the cloud returns a signed code with an expiry about 15 minutes ahead and writes an audit row naming them. *Cloud feature test.*
- **AC-3** Given a restaurant or till that does not exist, or one the technician may not see, then 404 and no code. *Cloud feature test (tenant boundary).*
- **AC-4** Given a valid code for this till, restaurant and username, when it is entered, then that person's Admin Mode password is cleared, the PIN is unchanged, and the audit row names the technician. *POS test with a test key pair (no cloud, no database where fakes allow).*
- **AC-5** Given a code for another till, another restaurant, another username, an expired code, a code signed by another key, a tampered code or an already-used code, then it is refused with its own message and nothing is cleared. *POS unit tests, one case each.*
- **AC-6** Given five wrong codes in a row, then the dialog locks out as the current one does, and a correct code during the lockout is not accepted. *POS test (existing limiter).*
- **AC-7** Given an empty code or an empty username, then the dialog says which field is missing and does not say "no such person". *POS widget test.*
- **AC-8** Given a person with no Admin Mode password or no such active person, then the message says so and nothing is changed. *POS test.*
- **AC-9** Given Arabic at 1024×700, then the dialog fits and a pasted code with spaces, line breaks or Arabic digits is accepted or refused cleanly. *Widget test; a person on a real till.*
- **AC-10** Given a till with no internet, then AC-4 works unchanged. *POS test (no network provider used).*
- **AC-11** The dialog no longer asks for or mentions the database administrator password. *POS widget test.* (If **Q3** is answered "keep", this changes.)
- **AC-12** No log, audit row or error message contains the code or any key. *Tests on both sides.*

## 9. Edge cases and failure modes
- **Clock:** an offline till's clock can be set back to extend a code. Mitigated by single use and device binding, not by the clock; stated as a residual risk.
- **Replay:** a copied code used again is refused once used (needs persistence on the till, **Q5**) and after expiry.
- **Wrong person:** a code names one username; it cannot clear another account or the PIN.
- **Several tills in one restaurant:** a code is for one till.
- **Offline licences and tills with no cloud record:** how the technician picks the till when there is no restaurant row in the cloud (an offline licence has a customer slug and a till id) is **UNVERIFIED** and is **Q7**.
- **Key rotation or compromise:** the key id lets XOrder retire a key; tills ship a set of accepted key ids (plan detail).
- **Typing:** the code is long (an Ed25519 signature alone is 64 bytes, roughly 100 base32 characters). It is for copying and pasting (chat, email, QR), not for reading aloud; see **Q2**.
- **Cloud outage:** issuance needs the cloud; a till can still verify offline. A restaurant with no way to reach XOrder cannot reset: said plainly in the dialog.
- **Arabic and RTL:** the code and the username are left-to-right inside an Arabic dialog; both languages for every message.
- **Plan and licence limits:** none apply; a lapsed licence does not block recovery (consistent with "cash-up is never gated").

## 10. Impact
| Area | Impact |
|---|---|
| Repos | `xorder-cloud` (API, Super Admin panel, tests) and `xorder-pos` (dialog, session controller, verifier, tests). |
| API and contract | A **new** cloud admin endpoint to issue a code (PROPOSED; not a READY contract item). The till does **not** call the cloud at reset time. The **code format** is the contract between the two and must be versioned and written down in `docs/coordination/` before building. |
| Data and migrations | POS: probably one small **additive** table to remember used code ids (Q5), applied by the existing migration runner, reviewed under `postgres-migrations.md`. Cloud: none required (cloud audit table exists); an issuance table is optional. |
| Permissions | A new platform capability; granting it to `SUPPORT` **widens** that role. |
| Localization | New and reworded strings in Arabic and English (dialog, messages, cloud panel). Arabic needs a native read. |
| Documentation | A feature folder for the technician reset; inventory row; ADR-006b D5.4 note. |
| Deploy order | **Cloud first** (can issue codes nothing yet accepts), then the POS release. Old tills keep the database-password dialog until upgraded. Rollback: remove the capability grant; the POS dialog change is reverted by a release. |
| Needs approval in `/implement` | the contract (code format and endpoint), the new capability and the `SUPPORT` widening, the new POS table, anything reaching `xorder-cloud` `main` (a push there deploys to production), and a `/security-audit` pass. |

## 11. Dependencies, known gaps, risks
- **Risk (named by the code's own comment):** the till verifies with a public key in the binary, so someone who can patch the app on the till can forge a pass. This design stops an honest insider and a leaked code; it does **not** stop a local attacker with operating-system control, and it does not claim to.
- **Risk:** reusing the licence signing key would make a licence-key compromise also a reset-code compromise (**Q4**).
- **Risk:** an unauthenticated lockout of a named account by wrong codes (the ADR's accepted trade-off) is unchanged.
- **Gap:** no per-technician identity exists in the till today (the actor is the literal `technician`).
- **Unrelated uncommitted work** sits in both working trees (the sign-in and setup work in POS; tender and financial-account edits in cloud); an implementer must keep the commits apart.
- **Known domain gaps leaned on:** none.

## 12. How it will be tested
Cloud PHPUnit feature tests on SQLite (AC-1, 2, 3, 12); POS unit tests with a generated Ed25519 test key pair and fakes for the signing side, so the verification is real and the cloud is not needed (AC-4 to AC-8, 10, 12); a POS widget test of the dialog in both languages and at 1024×700 (AC-7, 9, 11); a **contract test** that a code produced by the cloud service verifies in the POS verifier using the same fixture (the one test that proves the two sides agree). **Needs a person:** the dialog on a real till in Arabic, pasting a real code, and a technician doing a real issue-and-reset end to end. The real PostgreSQL clear and the nonce table are PostgreSQL-only and cannot be proved on the SQLite cloud suite or the fake-based POS suite.

## 13. Decisions and open questions
**Decided (2026-10-27, owner)**
- The reset credential is for **XOrder's technician only**.
- A fixed username and password in the app (`tech` / `2050`) is **not** the design (advised against; the owner then chose this signed-code proposal).

**Still open, each with my recommendation**
- **Q1 Who may issue codes?** Only `SUPER_ADMIN`, or also `SUPPORT` through a new capability. *Recommend a new capability, held by `SUPER_ADMIN` and `SUPPORT`.* (Widens a role.)
- **Q2 How does the code reach the restaurant?** A long signed string to copy and paste (chat, email, QR), or later a short code checked online. *Recommend the long signed string now.*
- **Q3 Keep the database-password route in the dialog?** *Recommend remove it from the dialog and keep only the machine-side command for a technician with access.*
- **Q4 Same signing key as licences, or a separate pair?** *Recommend a separate key pair and key id.*
- **Q5 Remember used codes on the till (a small additive table), or rely on expiry and device binding only?** *Recommend remembering them.*
- **Q6 Expiry.** *Recommend 15 minutes.*
- **Q7 Offline-licence tills with no restaurant row:** how does the technician name the till? *Recommend the till shows its identifier in the dialog and the technician types it.*
- **Suggestion, not asked for:** fix the misleading empty-field message of today's dialog on its own, regardless of this feature.

Next: `/implement pos-technician-reset-code` once Q1 to Q7 are answered or you accept the recommendations. It will need approved: the code format and the new cloud endpoint (contract), the new capability and any widening of `SUPPORT`, the new POS table, a security audit, and nothing reaching `xorder-cloud` `main` without your explicit go.

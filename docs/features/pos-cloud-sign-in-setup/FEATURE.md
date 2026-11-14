# Cloud till setup by signing in — pos-cloud-sign-in-setup

Status: proposed · 2026-11-08 · Source: the user's request, on the cloud wizard's licence screen: "I was thinking to change this for cloud, I think all of this not needed ?? It can be admin login or something like this ??" · Verified against: xorder-cloud `main` (working checkout is on `feat/finance-accounts-and-platform-updates-2026-10-26` `775bf0f` with unrelated uncommitted files; every backend claim below was read from `main`), xorder-pos `development` `9f1b7d2`

## 1. Summary
The **XOrder POS - Cloud** app is set up by **the business owner signing in with their xorder.io dashboard account** (owner only, D3). They do not type a licence key or a licence server address. After sign-in the till lists the branches and the existing tills, the owner picks one, and the till pairs itself. The licence arrives from the platform with the rest of the business data. The **Offline** app is unchanged.

## 2. Why
- The cloud wizard opens on a licence key and a "licence server" address (`http://localhost:8080` in the user's screenshot). A cloud customer already has a dashboard account, and asking them for a key and a server URL is the wrong question for someone who is not a technician.
- The reason the licence came first no longer holds. The licence was step one because it **decided the mode** (`setup_state.dart:29-41`). Since pos-split-apps each app fixes its own mode (`setup_state.dart:52-61`), so the cloud app already knows it is cloud before anything is typed.
- The licence is delivered anyway: the bootstrap bundle carries the signed licence (`xorder-cloud main: PosBootstrapService.php:160-169`), and the cloud app installs it "without anyone typing anything" (`apps/xorder_pos_cloud/lib/data/cloud/cloud_provisioning_repository.dart:371-380`). The typed key duplicates what pairing already gives.
- Venue models: helps every cloud venue (café, restaurant, cloud kitchen, food truck on the cloud plan), because the person installing the till is usually the owner. It assumes internet **during setup only**, which the cloud path already requires. It does not touch selling, tables or addresses.

## 3. Goal and success
- A cloud owner sets up a new till with: business address, username, password, pick branch, pick or name the till. No licence key, no server URL, no pairing code to copy.
- Success: no licence-key or licence-server field is visible in a release build of the cloud app; a till set up this way can open a shift; the owner's password is never written to disk.

## 4. Users, roles and permissions
| Who | May do it? | Source |
|---|---|---|
| Restaurant admin (owner) | **Yes, and only the owner** (D3) | Login reply `data.role` = `RESTAURANT_ADMIN` (`xorder-cloud main: AuthController.php` login returns `UserResource`, `UserResource.php:20`; `Enums/RoleEnum.php:20`). The owner holds every tenant capability, `pos.provision` included (`Models/User.php:134-138`) |
| Staff, even with `pos.provision` (e.g. a manager) | **No, on the till** (D3): refused right after sign-in, before any branch or terminal call | Login reply `data.role` = `RESTAURANT_STAFF` (`RoleEnum.php:21`) |
| Business without the POS feature | No | `feature:pos` on `register` (`routes/api.php:781-782`) and the dashboard terminal routes (`:657-664`) |
| Platform (Super Admin) user | No: login with a business address resolves to that tenant; no tenant capabilities for platform users (`User.php:140-142`) | |

No new permission identifier is introduced. **Note on D3:** the owner-only rule is checked by the till, on top of the server's own rule (`can:pos.provision`), which stays as it is. Staff with `pos.provision` can still create terminals and pairing codes **on the dashboard**; only the till's sign-in refuses them. This only narrows what the till offers; the server stays authoritative. A server-side owner-only rule was not requested, and would narrow existing dashboard access, so it is out of scope.

## 5. Today
**Already built (POS):** most of the sign-in road exists as "Path B", reached today through **"sign in instead"** on the pairing-code screen:
- `CloudApi.login` → `POST /api/auth/login` with `restaurant` (business slug), `username`, `password`; the JWT "is used for exactly one call … and is never stored by the till" (`packages/shared_module/lib/data/cloud/cloud_api.dart:111-123`).
- `listBranches` → `GET /api/dashboard/branches` (`cloud_api.dart:125-133`); `listTerminals` → `GET /api/dashboard/pos/terminals` (`:135-150`).
- Adopt an existing till: `issuePairingCode` → `POST /api/dashboard/pos/terminals/{id}/pairing-code`, then the till redeems it itself (`:152-167`, then `claimTerminal`, `:97-109`).
- New till: `registerTerminal` → `POST /api/pos/terminals/register` (`:169-187`).
- State: `operatorUsername`, `operatorPassword`, `pulledBranches`, `pulledTerminals`, `adoptTerminalId` (`setup_state.dart:131-133, 283-311`).
- Cloud path today: `licence → account → [branch, terminal if signing in] → connecting → [hardware] → summary` (`setup_state.dart:362-372`). Default method is the pairing code (`setup_state.dart:124-129`).

**Already built (cloud, on `main`):** login with optional `restaurant` slug (`Requests/Auth/LoginRequest.php`, `AuthController.php:85-113`); terminal list / create / pairing code under `can:pos.provision` (`routes/api.php:655-664`); self-register (`:781-782`); claim (`:778-779`, unauthenticated, throttled); bootstrap licence embed (`PosBootstrapService.php:160-169`, latest live licence for the restaurant).

**Missing:**
- The licence step is still first and mandatory on the cloud path.
- Sign-in is the secondary road, not the main one.
- The licence server field is shown (`setup_panes.dart:690-695`); its debug-only status is **UNVERIFIED** (no `kReleaseMode`/`kDebugMode` guard found in `features/setup` or `features/licensing`).
- Today the business slug comes **from the licence** (`tenant_slug`, `setup_state.dart:33-35`). Without the licence step, the owner must type it.

**UNVERIFIED:**
- Whether `register` or the pairing-code claim refuses when the licence's `max_terminals` is reached. No `max_terminals` check was found in the provisioning code on `main` (only in licence requests and `Pos/LicenceController.php:158`).
- Whether the bootstrap licence is checked against D9 (licence must name `cloud` and only `cloud`) before the till is declared ready, or only later at the start screen's licence gate.
- Whether a business account can have two-factor sign-in (none seen in `LoginRequest`).

## 6. Scope
**In (POS, cloud app path only):**
- The cloud wizard opens on **sign-in**: business address (typed as `____.xorder.io`, D5), username, password. No licence step and no licence-server field on this path.
- Remove the pairing-code entry screen from the cloud wizard (D2). Adopting an existing till still uses a pairing code internally (the till issues one and redeems it itself, `cloud_api.dart:152-167`); the owner never sees or types it.
- Refuse a non-owner right after sign-in (D3).
- After sign-in: choose the branch, then adopt an existing till or name a new one (the screens that exist today).
- Pairing, bootstrap, and installing the bundle's licence as today, then **checking the licence before "ready"**.

**Out:**
- The **Offline** app's wizard: unchanged; the licence key stays its first step.
- Child tablets (`childSteps`): unchanged.
- Any new backend endpoint or change to a response shape.
- Forgotten-password flow on the till (the owner resets it on the dashboard).
- SQLite for cloud tills (`pos-cloud-single-till-sqlite`).

## 7. Behavior and business rules
- **BR-1** The cloud wizard's first screen is sign-in, and it is the only way to set up a cloud till (D2). It asks for exactly three things: business address (`____.xorder.io`, the owner types only their part), username, password.
- **BR-2** The password and the JWT live in memory only, for the setup calls. They are never written to the setup progress store, the database, logs or crash reports, and are cleared when setup finishes or is cancelled. This is today's rule for Path B (`cloud_api.dart:111-112`), restated because it becomes the main road.
- **BR-3** Only the **owner** (`data.role` = `RESTAURANT_ADMIN` in the login reply) may continue past sign-in (D3). Any other account is refused at once with "Only the business owner can set up a till", and its JWT is discarded. Server refusals (no POS feature, read-only subscription) are still shown in plain words.
- **BR-4** The licence comes only from the platform (the bootstrap bundle). The cloud app never asks for a key or a server URL.
- **BR-5** Before the wizard says "ready", the installed licence must be live and name **only** the cloud mode (D9 of pos-split-apps, applied strictly from day one, D4). If the bundle had no licence, or one that names offline or both modes, the wizard stops on a refusal screen that says why and what to do, instead of leaving it to the start screen.
- **BR-6** Existing tills come first: when the business already has unclaimed tills, the wizard offers to adopt one before offering a new one (today's behavior, `cloud_api.dart:135-150`).
- **BR-7** There is no pairing-code road on the cloud till (D2). The "sign in instead" link and the pairing-code entry pane are removed from the cloud path.
- **BR-8** The cloud path shows no licence-server field at all (it has no licence step). The Offline wizard keeps its field as it is today (scope is cloud only, owner 2026-11-08).

## 8. Acceptance criteria
- **AC-1** Given a fresh cloud app, when the wizard opens, then the first screen asks for business address (shown as `____.xorder.io`), username and password, and no licence key, licence server or pairing-code field is visible anywhere on the cloud path.
- **AC-2** Given the owner's correct details, when they sign in, then the till shows that business's name and branch list from the server.
- **AC-3** Given a business with an unclaimed till in the chosen branch, when the owner picks it, then the till pairs as that till (pairing code issued and claimed by the till itself) and no new terminal row is created.
- **AC-4** Given the owner names a new till, when they continue, then a terminal is registered in the chosen branch and the till receives its device token and bootstrap.
- **AC-5** Given bootstrap carried a live cloud licence, when setup finishes, then the licence is installed and the till reaches the start screen able to open a shift.
- **AC-6** Given bootstrap carried no licence, or one that names offline or both modes, then the wizard shows a refusal that names the reason, and does not report "ready".
- **AC-7** Given a staff account (any role, including one with `pos.provision`), when it signs in with correct details, then the till shows "Only the business owner can set up a till", makes no branch, terminal, pairing-code or register call, and keeps no token.
- **AC-8** Given a wrong password, a wrong business address, or no internet, then a specific message is shown for each, the password field is cleared, and the other fields are kept.
- **AC-9** After setup (finished or cancelled), the password and JWT appear in no file the app wrote (setup progress store, config, database, logs).
- **AC-10** No licence server field is shown anywhere on the cloud wizard path.
- **AC-11** The Offline app's wizard is unchanged: licence first, as today.
- **AC-12** Every new message exists in Arabic and English, and the screen lays out right-to-left in Arabic.

## 9. Edge cases and failure modes
- **Offline / network loss mid-setup:** sign-in fails with a "no connection" message. If the connection drops after claim but before bootstrap, a retry must not register a second terminal. Today's `client_transaction_id` on register (`cloud_api.dart:172`) is the idempotency key; its retry behaviour on this path is **UNVERIFIED**.
- **Claimed but unlicensed:** the server has claimed the till but the bundle had no usable licence (BR-5). The terminal row stays claimed on the platform. The refusal tells the owner to check the licence on the dashboard, then retry. Whether retry re-pulls bootstrap with the same device token is **UNVERIFIED**.
- **Seat limit:** the business is at `max_terminals`. Server enforcement is **UNVERIFIED** (§5). If the server does not refuse, this description does not add a client-side check (the backend is authoritative).
- **Tenant boundary:** the business address scopes the login (`AuthController.php:99-101`); usernames are unique only within a business, so the address is required.
- **Brute force:** login is throttled server-side (`throttle:login`, `routes/api.php:91`); the till does not retry automatically.
- **Arabic/RTL and digits:** username and business address accept Latin; Arabic-Indic digits typed into the address are folded (existing `FoldDigitsFormatter`).
- **Subscription read-only:** pairing-code issue is under `subscription.writable` (`routes/api.php:661-664`). A business in read-only state cannot adopt a till. The message for this is a new string.
- **Two tills setting up at once and adopting the same unclaimed till:** the server's claim decides; the loser sees "this till was just taken" and returns to the list. Server behaviour is **UNVERIFIED**.

## 10. Impact
| Area | Change |
|---|---|
| POS shared (`packages/shared_module/lib/features/setup/`) | `cloudSteps` drops `licence`, and sign-in becomes the only method on the cloud path (the pairing-code pane and "sign in instead" are removed there; the offline and child paths are untouched). The sign-in pane gains the `____.xorder.io` business-address field (today the slug comes from the licence) and the owner-only check on the login reply's role. Add a licence check after bootstrap. Gate the licence-server field to debug. |
| POS cloud app (`apps/xorder_pos_cloud/`) | The licence-install result (`cloud_provisioning_repository.dart:371-380`) must be reported to the wizard, not swallowed, for BR-5. |
| POS offline app | None. |
| Cloud API | **None.** Every call is on `main` today. |
| Contracts | Uses `POS-BE-023` (READY) and existing dashboard/login routes. No new `POS-BE` item. |
| Data / migrations | None. |
| Permissions | None new; relies on `pos.provision`. |
| Localization | New strings: sign-in title and help, business address label and hint, refusals (no permission, no licence, wrong-mode licence, read-only subscription). Arabic and English. |
| Documentation | `docs/features/pos-setup-installer` (pending) and the pos-split-apps TECHNICAL note that the cloud wizard no longer opens on the licence. |
| Deploy order | POS only; nothing to deploy on the cloud side first. |

## 11. Dependencies, known gaps, risks
- **Risk: a business with no live licence** cannot finish setup on cloud, by design (BR-5). Today the Super Admin issues the licence with the tenant (`setup_state.dart:314-317`); a business created without one will now fail at the end instead of the start.
- **Risk: an owner's password typed on a shared machine.** Mitigated by BR-2 only: with no pairing-code road (D2), whoever installs a cloud till needs the owner present, or the owner's password.
- **Gap: seat-limit enforcement** on register/claim is unverified (§5).
- **Dependency and deploy order (D4):** pos-split-apps stage 6 (licences name one mode; branch `feat/licence-one-mode` `30b1529`, not on `main`) must reach `main`, and the business must hold a **cloud-only** licence, before a cloud till built from this can be set up. A licence naming both modes is refused (BR-5). The owner confirmed there is no active POS client yet (one business uses the menu only), so there are no existing tills to carry over.

## 12. How it will be tested
| AC | Test |
|---|---|
| AC-1, AC-11 | Widget tests of the wizard in each app (`fakeRepositoryOverrides(appMode: cloud/offline)`): first screen fields |
| AC-2, AC-3, AC-4, AC-7, AC-8 | Setup controller unit tests with a fake `CloudApi` (login reply, branch/terminal lists, 403, 401, network error) |
| AC-5, AC-6 | Cloud app test: `cloud_provisioning_repository` with a bundle carrying a live cloud licence, no licence, a wrong-mode licence |
| AC-9 | Unit test reading the setup progress store and config after a full fake run: no password or JWT |
| AC-10 | Cloud wizard widget test: no licence-server field on the cloud path |
| AC-12 | Widget test in `ar` locale (text direction, strings present); a person looks at the Arabic screen |
| End to end | `apps/xorder_pos_cloud/integration_test/` against a local API, owner account, one branch. Note: this suite currently walks a stale wizard and needs updating anyway |

## 13. Decisions and open questions
**Decided**
- 2026-11-08: the cloud wizard drops the licence key and licence server, and setup is by an "admin login" (the user's words).
- 2026-11-08: the Offline app is unchanged (it has no cloud account; its licence key stays).

- **D2** (2026-11-08, owner): **sign-in only.** No pairing-code road on the cloud till.
- **D3** (2026-11-08, owner): **owner only.** Staff, even with `pos.provision`, cannot set up a cloud till. Enforced by the till from the login reply's role; the server rule is unchanged (see §4 note).
- **D4** (2026-11-08, owner): **cloud-only licences, strictly.** No transition rule, because "there [are] no active clients yet, only one using menu".
- **D5** (2026-11-08, owner): the business address is asked as `____.xorder.io`.
- **D6** (2026-11-08, owner): **cloud only.** Nothing in the Offline app or the child-tablet path changes, including the Offline wizard's licence server field.

**Open**
- None that change this description. The UNVERIFIED items in §5 and §9 (seat limit, retry idempotency, concurrent adoption) are to be checked during `/implement`'s plan.

Next: `/implement pos-cloud-sign-in-setup`. Approval is needed for the plan only. No migration, no contract change and no cloud deploy are involved; the change narrows nothing for existing tills.

# Offline install — manual test runbook

Every step below was **executed on a real machine** against a real PostgreSQL on
2026-09-07, driving the app with mouse and keyboard. This is the record of what
was done, in the order it was done, so it can be repeated — and the record of
what it found.

It is deliberately a runbook rather than a report: the point is that somebody
else can sit down and reproduce the same install, or the same failures.

---

## 0. Environment

| Thing | Value used |
|---|---|
| Platform (licence issuance) | local docker stack, `http://localhost:8080` |
| PostgreSQL | host install, `127.0.0.1:5432` (`postgresql@16`) |
| POS database | `pos_desktop_db` |
| Till role | `pos_till` / `pos_till_dev` |
| Admin role | `pos_admin` (trust auth on localhost, any password) |
| Licence | `LIC-2026-0017`, offline, 1 terminal, 2 user accounts |
| Activation key | `PY0X-BSX7-2R2G-75B6` |

### Prerequisites the machine needed

These are **not** app bugs — they are what a real on-premises box has to have,
and are worth knowing because the wizard cannot create them for you:

```sql
-- pos_admin must be able to CREATE DATABASE. It is what the wizard's
-- "Build the database" step connects as.
ALTER ROLE pos_admin CREATEDB;

-- pos_till authenticates with scram in pg_hba.conf, so it needs a password
-- the installer actually knows.
ALTER ROLE pos_till PASSWORD 'pos_till_dev';

-- Only if you point the till at a database somebody ELSE created. From
-- PostgreSQL 15 the public schema no longer grants CREATE to everyone, so a
-- role that did not create the database cannot build tables in it.
ALTER DATABASE pos_desktop_db OWNER TO pos_admin;
ALTER SCHEMA public OWNER TO pos_admin;
```

### Running the app against a local platform

`PlatformEndpoint.base` is a build-time constant. A **debug** build now defaults
to `http://localhost:8080`; a release build goes to `https://xorder.io`. To
point anywhere else:

```bash
flutter run -d macos --dart-define=XORDER_PLATFORM=https://staging.example
```

---

## 1. Fresh terminal → setup wizard

1. Launch. The welcome screen reads **"This terminal has not been set up."**
2. Press **Ctrl+Shift+S**. The wizard opens at **step 1 of 11, Licence**.

## 2. Licence (step 1)

- A licence already installed on disk is **restored automatically** — the panel
  showed `LICENSED` and `Demo · one terminal` without retyping anything.
- To activate fresh: type the key, confirm **LICENCE SERVER** is the platform
  that issued it, press **Activate online**. Or **Activate from file** with the
  `.xlic`, which needs no network at all.

## 3. Language (2) → Setup type (3)

- Setup type showed **Cloud · NOT LICENSED** (greyed) and **Offline** selected.
  The licence decides this; the screen cannot be argued with. Correct.

## 4. Connection (4)

| Field | Value |
|---|---|
| Database name | `pos_desktop_db` |
| Port | `5432` |
| Database user | `pos_till` |
| Database password | `pos_till_dev` |

Press **Test connection**. Then **Continue**.

## 5. First administrator (5)

| Field | Value |
|---|---|
| POS_ADMIN password | `trusted` (any string — trust auth on localhost) |
| First person | `Amer Elsayed` |
| Their username | `manager` |
| Their PIN | `4821` |

Press **Build the database**. It reported, itemised:

```
This machine now has a database.
  pos_desktop_db was already there.
  The schema was already current.
  Demo and its first branch are on this machine.
  The roles were already there.
  Created Amer Elsayed as the owner.
  Granted pos_till and pos_admin what each one needs.
```

## 6. Branch (6) → Terminal (7)

- Branch: selected **Main** (`MAIN`, dine-in · takeaway · delivery).
- Terminal: named `Counter 1`, pressed **Register this terminal** → **Registered**,
  and a terminal id appeared.

Verify it landed:

```sql
SELECT t.name, t.id, b.code, t.claimed_at
FROM pos_terminals t JOIN pos_branches b ON b.id = t.branch_id;
-- Counter 1 | 0a0a6739-1965-42ae-8ed7-95d98187821d | MAIN | 2026-09-07 04:30:51+03
```

## 7. Hardware (8) → Money (9) → Catalogue (10) → Ready (11)

- Hardware: all optional, left empty.
- Money: `EGP · 2 decimals`, service `12% dine-in only`, VAT `14% on subtotal +
  service`, half-up rounding — flagged **FROM DEVICE CONFIGURATION**, i.e. held
  on the terminal until the restaurant sets its own in Management → Money.
- Catalogue: **Check the menu** → *"No menu on this terminal"*, expected on a
  new till.
- Ready: full summary, then **Open the till**.

## 8. Till start screen

`DEMO · POINT OF SALE`, Tenant Demo, Branch Main, Terminal Counter 1,
Catalog cached · 0 items. **Setup is complete at this point.**

## 9. Management → build the menu

1. **Management** → PIN keypad → `4821`.
2. **Back office password** → `trusted` → **Open Management**.
   (Menu and staff changes run on `pos_admin`, not the till's role. Asked once
   per session, never stored.)
3. **Menu** → **Add category** → `Hot Drinks` / `مشروبات ساخنة`.
4. **Add item** → `Turkish Coffee` / `قهوة تركي`, price `45.00`, SKU `HD-001`.

Verify:

```sql
SELECT name_en, price_minor, sku, is_available FROM pos_products;
-- Turkish Coffee | 4500 | HD-001 | true
```

## 10. Licence seat cap — verified live

Staff showed **"2 of 2 licensed · 2 in all"**. Pressing **Add somebody**
refused *before* asking for a name or PIN:

> This licence covers 2 user accounts, and they are all in use. Disable somebody
> who has left, or ask your supplier for a licence with more.

That is the full chain: `max_users` set in Super Admin → signed into the licence
claims → enforced on the till.

---

## What this run found

Bugs, root cause, fix. All fixed and re-verified in the running app unless
stated.

### 1. Wizard fields silently swallowed a keystroke — **fixed**

Typing `1 2 3 4` into THEIR PIN, one key per second, produced **three** dots.

`_Field` and `_PasswordField` rewrote their `TextEditingController` from the
parent's value on any rebuild where the two differed. The setters transform
what they are given (`setOwnerPin` keeps only digits) and also churn other
state, so a rebuild could land carrying the value from *before* the last
keystroke and write it back over the field.

The character lands in a PIN or a database password, so nothing looks wrong
until a credential typed perfectly correctly is refused. Fixed by never
rewriting the controller while the field has focus.

### 2. Offline terminal registration always refused — **fixed**

Step 7 reported *"That username and password were not accepted."*

Offline registration authenticates against `pos_staff` on this machine and read
`operatorUsername`/`operatorPassword` — the **cloud Sign in** fields, which the
offline path no longer collects since its account step became First
administrator. It sent an empty username every time, on the last step of the
wizard. It now authenticates as the administrator created at step 5.

### 3. `42501: permission denied for schema public` — **fixed (diagnosis)**

Pointing the till at a pre-existing database. Now its own `PosDbFailure` case
naming the remedy; `bin/pos_migrate.dart` prints the two `ALTER` statements.

### 4. "Connected, but the database did not answer as expected" — **fixed**

Said when the database did not **exist**. Now `PosDbFailure.missingDatabase`,
matched after the auth check so a missing *role* stays an auth problem.

### 5. Activation failures were all one sentence — **fixed**

Unreachable platform, wrong platform, throttled, revoked and genuinely-unknown
key all reported as "that licence key was not recognised". Five cases now, and
the 404 names the address that refused it.

---

### 6. Four UX findings — **fixed**

| Finding | Where | Fix |
|---|---|---|
| *"This licence does not cover Cloud, so the terminal was set to Offline"* shown in the **red error bar** on a healthy install | Licence, step 1 | Demoted to the notice bar |
| **Test connection succeeded silently** — its only signal was the absence of red | Connection, step 4 | Says which database answered |
| The PIN keypad **shifted** when its error line appeared, so fast entry landed on the wrong keys | Management PIN | Space reserved, keypad cannot move |
| *"the menu refreshes in the background"* — cloud wording on a till that syncs nothing | Catalogue, step 10 | Offline wording |

### 7. A shift could be opened onto a screen with no way out — **fixed**

Opening the first shift lands on **Pick a table**. A branch that has just been
installed has no tables — a manager adds them in Management -> Floor — so the
screen was a header, three zeroed counters, and nothing else. No tile to tap,
no button, no back. The shift was open and the only exit was quitting the app.

The branch also sells takeaway and delivery, and there was no way to reach a
sale that did not go through seating somebody first.

The floor now says where tables are made, and carries **Sell without a table**
(which sets the ticket to the first non-dine-in type the branch actually sells)
and **Back to the till**. A branch whose `supported_order_types` has no
`dine_in` at all now skips the floor entirely, which is what the screen's own
doc comment always claimed happened.

### 8. A PIN longer than four digits locked its owner out — **fixed**

Management -> Staff accepted "four or more digits" and said so. Every keypad in
the till — sign-in, lock, Management, supervisor override — is hard-capped at
four and **submits on the fourth digit**; there is no confirm key. So a
six-digit PIN could be created and handed over, and the person it belonged to
could never sign in: the keypad refused the fifth digit and sent the first four.

`PinRules.length` is now the single constant every keypad and every creation
form reads, `PinRules.isWellFormed` is the one check, and the wizard's
`4..12` — which had the same defect from the other end — follows it.

---

## Security review (§12)

| Item | Finding |
|---|---|
| Plaintext database password | Not in `config.json`. Held in `secrets.json`, mode `0600`, beside it. **Hardened:** the file was written at the umask default and chmodded afterwards, so the password sat at `0644` for the length of the write; it is now created empty, restricted, then filled. |
| Plaintext admin password | None stored. The `pos_admin` password is asked once per Management session and never written. |
| Password hashing | PBKDF2-HMAC-SHA256, 120 000 iterations, 16-byte per-row salt, constant-time compare. |
| Editable licence file | `licence.xlic` is Ed25519-signed; the public key is compiled into the binary. Editing it fails verification. |
| Hardcoded secrets | None reachable. `lib/data/fakes/fake_repositories.dart` hardcodes PIN `1234` — **nothing in `lib/` or `bin/` imports it**, only tests, so it is tree-shaken out of a release build. It would be better placed under `test/support/`; left where it is because another workstream has the file open. |
| Terminal authentication | Terminal id + claim recorded in `pos_terminals`; revocation is honoured at the till. |
| Least privilege | **Fixed — see below.** |
| Sensitive logs | The database probe logs role@host:port/database and the raw driver message. No password, PIN, token or secret is logged anywhere. |
| Debug credentials / backdoors | None found in the shipped paths. |

### The one real finding: the till role could escalate to owner, offline

`LocalBootstrap.tillGrants` granted `pos_till` INSERT/UPDATE on `pos_staff` and
INSERT/UPDATE/DELETE on the whole catalogue. That block exists for
`BootstrapSeeder`, which replaces the local cache with the platform's copy, and
the code comment defended it explicitly:

> a stolen till credential could rewrite the local *cache*, but on a cloud till
> the cache is not authoritative — every order is re-priced server-side, so
> repricing the display buys an attacker nothing at settlement.

**That reasoning does not survive going offline.** There is no server-side
second opinion; this database *is* the restaurant. With those grants, the till
password — a `0600` file on the same machine — could reprice the menu for real,
and through `pos_staff` could point somebody's row at the owner role or
overwrite a PIN hash, reaching Management without ever knowing the
administrator's password.

The seeder never runs offline (`syncCatalogue` early-returns without a
platform) and Management authors the menu and staff over the **admin**
credential, so the grants bought an offline install nothing.

They are now conditional on `cloudSeeding:`, which defaults to **off** — the
safe answer is the one an omission produces — and the offline list additionally
**REVOKEs** them, so a branch server built before this change is downgraded the
next time grants are applied rather than staying permissive forever.

Verified on the live install:

```
pos_branches       | SELECT
pos_categories     | SELECT
pos_dining_tables  | SELECT
pos_order_payments | INSERT,SELECT
pos_orders         | INSERT,SELECT
pos_products       | SELECT
pos_restaurants    | SELECT
pos_shifts         | INSERT,SELECT,UPDATE
pos_staff          | SELECT
```

Re-apply to an existing install with:

```bash
POS_PG_PASSWORD=… dart run bin/pos_migrate.dart --host 127.0.0.1 --database pos_desktop_db --user postgres --grant-to pos_till
```

Add `--cloud-till` only for a terminal that syncs from XOrder Cloud.

## Not yet exercised

Cashier sale, receipt, reopen/void/refund, shift close, internet-off retest,
and the second LAN terminal.

Restart persistence **is** verified: the app relaunches straight into the till
with no wizard, and a shift left open comes back as
*"Resume SHIFT #0001 — the drawer was never closed, so the shift is still
yours."*

---

## Automated coverage added alongside

- `test/features/setup_typing_test.dart` — types into the real wizard, asserts
  every character survives.
- `test/data/pos_db_failure_test.dart` — every branch of the failure classifier.
- `test/features/setup_input_rules_test.dart` — database-name identifier rule,
  PIN bounds, refusals reaching the log.
- `test/features/offline_licence_activation_test.dart` — activation by key
  alone, and each failure diagnosis.
- `test/core/pin_rules_test.dart` — the creation forms and the keypads agree on
  one length, so no PIN can be created that cannot be typed.
- `test/features/sale_flow_test.dart` — a branch with no tables still offers a
  way to sell and a way back.
- `test/data/till_grants_test.dart` — the offline till role is read-only on the
  menu, the staff and the restaurant, still writes orders and shifts, and the
  permissive default is the one that had to be asked for.
- `test/data/till_grants_enforced_test.dart` (integration) — the same, applied
  to a real role on a real server **starting from the permissive set**, so it
  proves the downgrade, not just the fresh install. PostgreSQL refuses every
  escalation with `42501`.
- `test/data/file_secret_store_test.dart` — the secret file is owner-only after
  repeated writes and leaves no temporary behind.
- `test/data/offline_end_to_end_test.dart` (pre-existing) — passes against the
  real PostgreSQL:

```bash
POS_PG_HOST=127.0.0.1 POS_PG_USER=amerelsayed POS_PG_PASSWORD=trusted \
  flutter test test/data/offline_end_to_end_test.dart --tags integration
```

Note it needs a role with **CREATEDB** and a **non-empty** password: it passes
an empty admin password (fine only on a trust container), and an empty
`POS_PG_PASSWORD` fails inside the credential store.

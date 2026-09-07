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

## Open UX findings (not yet fixed)

| Finding | Where |
|---|---|
| *"This licence does not cover Cloud, so the terminal was set to Offline"* is shown in the **red error bar** on a healthy offline install. It is a notice; the next screen already says it calmly with a `NOT LICENSED` chip. | Licence, step 1 |
| **Test connection succeeds silently.** No confirmation at all — you cannot tell it ran. | Connection, step 4 |
| The PIN keypad **shifts position** when its error line appears or clears, so fast entry lands on the wrong keys. Real problem on a touchscreen. | Management PIN |
| *"the menu refreshes in the background"* — cloud wording on a till that syncs nothing. | Catalogue, step 10 |

## Not yet exercised

Cashier sale, receipt, reopen/void/refund, shift open and close, internet-off
retest, restart persistence, and the second LAN terminal.

---

## Automated coverage added alongside

- `test/features/setup_typing_test.dart` — types into the real wizard, asserts
  every character survives.
- `test/data/pos_db_failure_test.dart` — every branch of the failure classifier.
- `test/features/setup_input_rules_test.dart` — database-name identifier rule,
  PIN bounds, refusals reaching the log.
- `test/features/offline_licence_activation_test.dart` — activation by key
  alone, and each failure diagnosis.
- `test/data/offline_end_to_end_test.dart` (pre-existing) — passes against the
  real PostgreSQL:

```bash
POS_PG_HOST=127.0.0.1 POS_PG_USER=amerelsayed POS_PG_PASSWORD=trusted \
  flutter test test/data/offline_end_to_end_test.dart --tags integration
```

Note it needs a role with **CREATEDB** and a **non-empty** password: it passes
an empty admin password (fine only on a trust container), and an empty
`POS_PG_PASSWORD` fails inside the credential store.

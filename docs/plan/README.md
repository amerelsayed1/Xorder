# Xorder work plan

**As of 2026-11-07.** Organised by the four parts of the product. Each part has its own file with what is done, what is next (as specs), and what waits on the owner. Nothing here has been pushed or deployed.

## Where we are

Today's work is merged on a local `development` branch in each repo and verified there. The next work is the four scopes below; the two biggest items are the dashboard order sheet (Business Admin) and sending the customer with a till sale (POS cloud).

## Branches

| Repo | Branch | Head | Holds | Verified |
|---|---|---|---|---|
| xorder-pos | `development` | `3052a53` | local `main` + parked-check fixes (XORD-044/045/046, void guard), green test suite (XORD-029), rename to "business" (migration 64), provisional receipt (XORD-058) and its follow-up, till sends the customer (G2) | `scripts/check.sh` 2026-11-08: analyze clean, unit 3544 passed, PostgreSQL 1247 passed |
| xorder-cloud | `development` | `c2191fb` | `origin/main` + finance branch + server-priced diner orders (XORD-047) + order sheet (XORD-048) + customer name on till orders (G2) | full suite 1186 / 1186; `pnpm --filter @xorder/web build` |

Neither branch has an upstream. Not on them yet: the other sessions' uncommitted work — guest paging (cloud checkout) and the POS dropdown changes (`fix/dropdown-consistency`). See [release.md](release.md).

## The four scopes

| Scope | File | Done today | Next | Waiting on the owner |
|---|---|---|---|---|
| **Super Admin** | [super-admin.md](super-admin.md) | content languages made Super-Admin-only | tell tills when the Super Admin changes a language | XORD-055; cloud rename plan |
| **Business Admin + menu** | [business-admin-and-menu.md](business-admin-and-menu.md) | diner orders priced by the server (XORD-047); order sheet matches the receipt (XORD-048); customer name on till orders (G2) | XORD-049 to 053, 057 | Docker image prune |
| **POS offline** | [pos-offline.md](pos-offline.md) | tills can't overwrite or underpay checks; rename; green suite | small fixes (XORD-059, 054, 056); waiter app stages 2–3 | restore the `aziz_db` till |
| **POS cloud** | [pos-cloud.md](pos-cloud.md) | provisional receipt, cloud invoice number (XORD-058); end-to-end test passed | send the customer with a sale | XORD-055 |

Cross-cutting: merging the leftovers and releasing — [release.md](release.md).

## Features, grouped

Related work across the four scopes, grouped by feature. Each item in a scope file carries its group (`G1`–`G9`). Build a group's parts in the order shown; scopes that a group touches deploy separately (cloud first).

### G1 — Receipt, invoice number and order sheet
One sale should read the same on the till's receipt, in the till's history and on the dashboard.

| Part | Scope | Status | Order |
|---|---|---|---|
| Cloud's invoice number; PROVISIONAL first print (XORD-058) | [POS cloud](pos-cloud.md) | done | — |
| XORD-058 follow-up: receipt dialog and history update to the cloud's number | [POS cloud](pos-cloud.md) | done (POS `development` `3052a53`) | — |
| Dashboard order sheet matches the receipt (XORD-048) | [Business Admin](business-admin-and-menu.md) | done (cloud `development` `c2191fb`) | — |

### G2 — Customer on till orders (XORD-001 "Remaining")
A till sale for a named customer shows that customer on the dashboard.

| Part | Scope | Status | Order |
|---|---|---|---|
| Cloud fills `customer_name` / `customer_phone` from the customer record | [Business Admin](business-admin-and-menu.md) | done (cloud `development` `c2191fb`) | — |
| Till sends the customer's platform id with the sale | [POS cloud](pos-cloud.md) | done (POS `development` `3052a53`); end-to-end check not run | — |

### G3 — Tills learn about cloud changes
What the business or the Super Admin changes in the cloud reaches running tills, and how fast.

| Part | Scope | Status | Order |
|---|---|---|---|
| Content languages are Super-Admin-only, business-wide | [Super Admin](super-admin.md) | done | — |
| Bump `pos_config_version` when the Super Admin changes a language | [Super Admin](super-admin.md) | ready | any time |
| XORD-055: how fast a staff change reaches a running till | [Super Admin](super-admin.md), [POS cloud](pos-cloud.md) | waiting (owner) | after the decision |

### G4 — Diner menu and online ordering
The QR / online menu a diner orders from.

| Part | Scope | Status | Order |
|---|---|---|---|
| Diner orders priced by the server (XORD-047) | [Business Admin](business-admin-and-menu.md) | done | — |
| Guest paging (other session's work) | [Release](release.md) | waiting (commit) | merge into `development` |
| XORD-051 category pill, XORD-052 "؟T3", XORD-053 Send button | [Business Admin](business-admin-and-menu.md) | ready | any time |

### G5 — Cloud orders reach the POS
Pickup, delivery and table orders placed in the cloud appear on the till.

| Part | Scope | Status | Order |
|---|---|---|---|
| `pos-incoming-cloud-orders` | [POS cloud](pos-cloud.md) | later | after guest paging (G4) is merged — same files |
| Table requests on handhelds (waiter WS8) | [POS cloud](pos-cloud.md) | later | after G5 and G6 stage 2 |

### G6 — Tables, checks and the waiter app
Table service: checks shared by several tills, rounds, kitchen tickets, the dashboard's tables.

| Part | Scope | Status | Order |
|---|---|---|---|
| Parked checks versioned; no overwrite, underpay or wrong void (XORD-044/045/046) | [POS offline](pos-offline.md) | done | — |
| Waiter stage 2 — rounds as records (migration 65) | [POS offline](pos-offline.md) | ready | 1 |
| Waiter stage 3 — kitchen tickets | [POS offline](pos-offline.md) | ready after stage 2 | 2 |
| Later waiter stages (branch service, waiter role, device limit, handheld) | [POS offline](pos-offline.md) | later | 3 |
| XORD-049 Complete hint for table orders, XORD-050 dining-areas link | [Business Admin](business-admin-and-menu.md) | ready | any time |

### G7 — Till setup, pairing and start-up
Getting a till installed, registered against a branch, and opening reliably.

| Part | Scope | Status | Order |
|---|---|---|---|
| End-to-end on the local stack (licence, pairing, sync, sale) | [POS cloud](pos-cloud.md) | done | — |
| XORD-057 a branch must have a code before a till registers | [Business Admin](business-admin-and-menu.md) | ready | any time |
| XORD-059 retry after a failed database open; XORD-054 setup error names the cause; XORD-056 shortcut | [POS offline](pos-offline.md) | ready | any time |
| Upgrade rule: `pos_migrate` before the new till starts | [POS offline](pos-offline.md) | rule | every release |
| Restore the offline `aziz_db` till on this Mac | [POS offline](pos-offline.md) | waiting (owner) | — |

### G8 — "Business", not "restaurant"
| Part | Scope | Status | Order |
|---|---|---|---|
| POS code and database renamed (migration 64) | [POS offline](pos-offline.md) | done | — |
| Cloud rename, multi-step production plan | [Super Admin](super-admin.md) | waiting (owner) | after guest paging is committed |

### G9 — Quality and release
| Part | Scope | Status | Order |
|---|---|---|---|
| POS test suite green (XORD-029) | [POS offline](pos-offline.md) | done | — |
| Merge leftovers, release cloud then POS | [Release](release.md) | waiting | last |
| Docker images prune (local machine only) | [Business Admin](business-admin-and-menu.md) | waiting (owner) | any time |

## Decisions recorded

| Date | Decision |
|---|---|
| 2026-11-06 | **A5:** diner orders without item ids are refused for every business ("please refresh"); no legacy window. |
| 2026-11-07 | **The POS is a first version:** no compatibility code for older tills; migrations stay numbered and additive. |
| 2026-11-07 | **Naming:** the POS code and database say "business" (Arabic المنشأة), not "restaurant". The cloud keeps its names until its own plan. |
| 2026-11-07 | **XORD-058:** the cloud's invoice number is the invoice number; a cloud till's first print says PROVISIONAL. |
| 2026-11-07 | **Content languages:** one setting for the whole business, set by the Super Admin only. Per branch, only item availability varies. |

## How to verify

| What | Command |
|---|---|
| Cloud API | `cd apps/xorder-cloud/apps/api && php -d memory_limit=2G vendor/bin/phpunit` (in a worktree without `.env`, prefix `APP_KEY="base64:$(openssl rand -base64 32)"`) |
| Cloud Vue apps | `cd apps/xorder-cloud && pnpm build` |
| POS, everything | `cd apps/xorder-pos && scripts/check.sh` |
| POS, PostgreSQL only | `flutter test --tags integration --concurrency=1` with `POS_PG_*` set |
| Docs harness | `bash scripts/harness/verify.sh` |

## How to use this folder

- One file per scope. Every item carries **Status** (`done`, `ready`, `waiting`, `blocked`), **Group**, **Repo**, **Approval** and **Closes**.
- When an item moves, update its scope file, the scope table **and** its group's table above. A new item joins an existing group, or a new `G` number.
- Tick a box in the QA tracker only for a criterion an automated test that actually ran proves, and name the test.
- Claude never pushes, merges to `main`, tags or deploys; the owner does, after `/release-check`.

## Related

- QA tracker: [`docs/qa/XORDER_QA_FINDINGS.md`](../qa/XORDER_QA_FINDINGS.md)
- Test reports: [production scenario 2026-11-06](../testing/reports/2026-11-06-scenario-table-order-production.md), [cloud till on the local stack 2026-11-07](../testing/reports/2026-11-07-manual-pos-cloud-till-local.md)
- Feature folders: [`dashboard-order-receipt-parity`](../features/dashboard-order-receipt-parity/FEATURE.md), [`waiter-app`](../features/waiter-app/TECHNICAL.md), [`pos-incoming-cloud-orders`](../features/pos-incoming-cloud-orders/TECHNICAL.md)

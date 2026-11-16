# Cloud cutover plan: production from `Xorder-Menu` to the monorepo

Status: **DRAFT, not approved, nothing executed.** Written 2026-11-16.
Owner approval is required before any step marked **[PROD]**. Rules: `CLAUDE.md` (non-negotiable safety), `.claude/rules/production-safety.md`, `.claude/rules/postgres-migrations.md`.

## 1. Goal and scope
Make `https://xorder.io` deploy from this monorepo (`apps/xorder-cloud`) instead of the old `Xorder-Menu` repo, **without changing what clients see during the switch**. Two separate changes, deliberately not combined:

| Phase | Changes for clients? |
|---|---|
| A. Cutover (this plan, steps 1-7): the server pulls from the monorepo, same code as today | No |
| B. First feature deploy (section 6): ships the 33-file difference below | **Yes** |

## 2. Verified facts (checked 2026-11-16)
- `xorder.io` and `www.xorder.io` resolve to `51.68.229.216` (OVH VPS); DNS is at Namecheap.
- `make deploy-check` (read-only) showed: `/opt/xorder/deploy.sh` exists (Sep 27); server HEAD `dd1a6c6` ("Merge pull request #11 from amerelsayed1/development", 2026-11-10); remote `git@github.com:amerelsayed1/Xorder-Menu.git`.
- `dd1a6c6` is an ancestor of the monorepo `HEAD`, so no history is lost.
- `git diff dd1a6c6 HEAD:apps/xorder-cloud` = **33 files, +732 / -842** (section 5).
- `deploy.sh` (read from its header, not executed): DB backup first and aborts if it fails, never `down -v`, health-gated auto-rollback, touches only the xorder compose project, lock file, logs to `./logs`.
- The monorepo has **no git remote** yet (`CLAUDE.md`).

## 3. UNVERIFIED (confirm before relying on)
- Whether the server's working tree equals `dd1a6c6` (local edits, untracked changes, or a newer deploy).
- The server's directory layout beyond `deploy.sh` (where `.env.production`, `backups/`, `logs/`, compose files live relative to the clone).
- Whether `/opt/xorder` is the clone root and whether the compose file is `docker-compose.cohost.yml` there.
- Whether a check constraint or column type on `orders.status` accepts the new `PENDING` value.
- Whether any POS-facing response other than `/pos/orders` (for example `/pos/bootstrap`) can return a `PENDING` WhatsApp order. Section 5a covers what was checked.
- GitHub `production` environment reviewers, and the values of repo variables `XORDER_DEPLOY_PATH` / `XORDER_COMPOSE_FILE`.

## 4. Venue-model impact (`.claude/rules/domain-expert.md`)
Cutover alone: none. Phase B: removing the Live board affects restaurants and food trucks that watch orders on the dashboard; the new `PENDING` WhatsApp order flow affects every venue taking WhatsApp orders (cafes, cloud kitchens). Orders must never be lost or double-accepted during a deploy window.

## 5. What Phase B would change (diff `dd1a6c6` to monorepo `apps/xorder-cloud`)
1. Dashboard **Live board removed** (`LiveBoardView.vue`, nav entry, route); moved to POS per its commit notes.
2. WhatsApp orders get new status **`PENDING`** (accept or reject before it is a real order): `OrderStatus`, `PublicOrderController`, `Dashboard\OrderController`, menu SPA.
3. Capability **`live.view` removed**; `orders.read` / `bills.read` now need `orders.view` / `bills.view`.
4. Smaller: pickup board, insights, stats, `ReportService`, `lang/` files, `routes/api.php`, orders view, i18n.
5. ~~Migration `2026_11_10_000100_remove_live_view_from_roles.php` rewriting `roles.capabilities`~~ **Removed on branch `fix/live-view-no-data-rewrite`** (release-check A2). Stored role rows are not touched; the removed `live.view` value is ignored at read time, so roles holding only `live.view` lose order and bill reads exactly as designed, but nothing is rewritten and a code rollback restores the old behaviour. Covered by `StaleLiveViewCapabilityTest` (not yet merged to `main`).
6. ~~An already-shipped migration (`2026_08_23_000400_grant_live_view_...`) was edited~~ **Restored byte-identical to the server commit `dd1a6c6`** on branch `fix/live-view-no-data-rewrite` (release-check A3). To keep it loading, `TenantCapability::LIVE_VIEW` is kept as a retired, `@deprecated` case that every user-facing path excludes (`active()`, `values()`, `tryFromActive()`, Gate definitions, role editor, Admin default role). Covered by `StaleLiveViewCapabilityTest`.
7. `.github/workflows/deploy.yml` removal in the diff is only the workflow moving to the repo root.

## 5a. Backward compatibility (checked 2026-11-16, by reading code and the ledger; no tests run)

**Result: the 33-file diff does not change any route the POS calls.** With the roles rewrite removed (section 5, item 5) it is backward compatible at the API level; the only behaviour change is that roles holding `live.view` without `orders.view` / `bills.view` lose those reads.

POS cloud client calls (from `apps/xorder_pos_cloud/lib/data/cloud` and `shared_module/lib/data/cloud`): `/pos/bootstrap`, `/pos/orders`, `/pos/refunds`, `/pos/shifts`, `/pos/cash-movements`, `/pos/customers`, `/pos/license/check`, `/pos/terminals/{register,claim,heartbeat}`, `/dashboard/branches`, `/dashboard/pos/terminals`, `/pos/branch/sales[/summary]`.

| Check | Finding |
|---|---|
| Routes changed in `routes/api.php` | Only the dashboard orders group: gate widened to `system_ordering\|pos\|whatsapp_ordering`, new `POST orders/{order}/accept` and `/reject`, `orders.read` / `bills.read` lose the `live.view` alternative. No `/pos/*`, `/dashboard/branches` or `/dashboard/pos/terminals` route changed. |
| POS controllers/services in the diff | None (`Controllers/Pos`, `PosOrderService`, `PosRefundService` are not in the diff). |
| `PENDING` reaching POS | `PENDING` is set only in `PublicOrderController` for WhatsApp orders; `Pos\OrderController` queries `channel = 'pos'`. `/pos/bootstrap` not checked (UNVERIFIED). |
| `PENDING` in cloud reports | Excluded from stats, insights, `ReportService` and the pickup board. |
| Old dashboard browser tabs | Do not know `PENDING` and the removed `live.view`; a hard reload after deploy picks up the new bundle. |

**`/api/pos/branch/sales` and `/sales/summary` (open point 1, resolved):** these are **POS-BE-029, status PROPOSED** (`POS_TO_BACKEND.md` line 1550; `BACKOFFICE_TO_CLOUD.md` CB-11 "absent"). The POS client was built against a fake HTTP layer. A search of the cloud `routes/` and `app/` at both the server commit `dd1a6c6` and the monorepo `HEAD` finds **no such route in either**, and git history has no commit adding one. So these calls return 404 today and will return 404 after Phase B: the deploy changes nothing here. Per `CLAUDE.md` the POS must not integrate against PROPOSED items; whether the POS shows these screens to users on a cloud till is UNVERIFIED (not traced).

**Other compatibility items**
- `POS-BE-033` (`GET /api/pos/incoming`, accept/reject of online orders) is PROPOSED and its cloud half is not in either version's routes. Not part of this deploy.
- Rolling back code (`make deploy-rollback`) fully restores behaviour: no tenant data is rewritten and no shipped migration is modified (after the fix on `fix/live-view-no-data-rewrite`).
- `packages/api-client` (Vue apps) was not compared against the changed dashboard routes. The only menu-app change in the diff is a locale file.
- No automated tests were run for this section (cloud suite, POS suite, contract tests). Before Phase B run the cloud suite (`php artisan test`) and `/project-testing`.

## 6. Plan

### Phase A: cutover, same code
Pre-conditions: owner approval; a quiet window; someone able to SSH in.

1. **Create the remote** (GitHub repo for the monorepo) and push `main`. **[needs approval]** Do not push until approved; pushing `main` of a repo with the cloud deploy workflow must not auto-deploy (the workflow is manual-only, `workflow_dispatch`).
2. **Inspect the server, read-only.** Confirm `git status` and `git diff` are clean in `/opt/xorder`, record `git rev-parse HEAD`, list `.env.production`, `backups/`, `logs/`, the compose file and volume names. Fills section 3.
3. **Fresh backup. [PROD]** Run the server's existing backup (the one `deploy.sh` uses); confirm the file exists and is non-empty. Do not touch `db-backups/` locally.
4. **Find a commit-identical starting point.** Make the new clone's deployed commit contain exactly the code of `dd1a6c6` (see option below). Do **not** deploy monorepo `HEAD` in this phase.
5. **Switch. [PROD]** Preferred: a **second clone** of the monorepo beside the old one (e.g. `/opt/xorder-mono`), copy only git-ignored runtime files (`.env.production`, any local compose override) into `/opt/xorder-mono/apps/xorder-cloud`, check out the commit from step 4. Leave `/opt/xorder` untouched as the rollback target. Set repo variable `XORDER_DEPLOY_PATH` and the Makefile `DEPLOY_PATH` to `<clone>/apps/xorder-cloud`.
6. **Verify without deploying.** `make deploy-check DEPLOY_PATH=<new path>`; compare `docker compose config` output of old and new paths (same services, same volumes, same env file).
7. **First deploy of identical code. [PROD]** `make deploy DEPLOY_PATH=<new path>`; expect a restart and a passing health check, no migration changes. Watch `make deploy-logs` and `https://xorder.io`.

Rollback for Phase A: point the Makefile and variable back to `/opt/xorder` and run `make deploy`; the old clone and its files were never modified. `make deploy-rollback` goes back one commit only.

Option for step 4: tag or branch in the monorepo at the commit whose `apps/xorder-cloud` tree equals `dd1a6c6` (verify with `git diff --stat dd1a6c6 <commit>:apps/xorder-cloud` showing no differences), because old commits keep un-prefixed paths.

### Phase B: ship the 33-file difference (separate change, own approval)
1. `/release-check` on the monorepo cloud code; read the new migration against `postgres-migrations.md`; owner confirms the Live board removal and the capability change are intended.
2. **Impact list, read-only, on the server:** which roles lose access. Run by the owner (or approved by them), a SELECT only:
   ```sql
   SELECT restaurant_id, id, name FROM roles
   WHERE capabilities::text LIKE '%live.view%'
     AND capabilities::text NOT LIKE '%orders.view%'
     AND capabilities::text NOT LIKE '%bills.view%';
   ```
   Each row is a role that would lose order and bill reads. Notify those restaurants or fix their roles first. (`capabilities` is JSON text per the migration comment; Postgres column type unverified.)
3. Fresh backup, quiet window, then `make deploy`.
4. After: log in as a restaurant admin and a staff role, create a WhatsApp order, accept and reject it, check the dashboard orders view.
5. Rollback: `make deploy-rollback` is enough; no tenant data was rewritten. The impact list in step 2 is still worth running so affected restaurants are warned.

## 7. Risks
| Risk | Mitigation |
|---|---|
| New clone missing `.env.production` or volumes | Step 2 and 6 comparison; old clone kept as rollback |
| Server tree differs from `dd1a6c6` | Step 2 clean check before anything else |
| Deploy ships feature changes by accident | Phase A deploys only the commit-identical tree |
| Roles lose order/bill reads (by design) | Section 6 B.2 impact list and owner notice; no data rewrite, so no data to restore |
| Older POS builds vs `PENDING` status | Check `docs/coordination/` ledger; additive-only contract rule |
| Secrets exposure | SSH key lives in Doppler `xorder/prd`; the deploy key printed once in a chat session and should be rotated |

## 8. Not done
No push, no server change, no deploy, no GitHub variable change. Only read-only checks were run (`make deploy-check`, DNS lookup, local git diffs).

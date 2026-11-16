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
- POS compatibility with `PENDING` orders and the removed `live.view` capability (see `docs/coordination/`).
- GitHub `production` environment reviewers, and the values of repo variables `XORDER_DEPLOY_PATH` / `XORDER_COMPOSE_FILE`.

## 4. Venue-model impact (`.claude/rules/domain-expert.md`)
Cutover alone: none. Phase B: removing the Live board affects restaurants and food trucks that watch orders on the dashboard; the new `PENDING` WhatsApp order flow affects every venue taking WhatsApp orders (cafes, cloud kitchens). Orders must never be lost or double-accepted during a deploy window.

## 5. What Phase B would change (diff `dd1a6c6` to monorepo `apps/xorder-cloud`)
1. Dashboard **Live board removed** (`LiveBoardView.vue`, nav entry, route); moved to POS per its commit notes.
2. WhatsApp orders get new status **`PENDING`** (accept or reject before it is a real order): `OrderStatus`, `PublicOrderController`, `Dashboard\OrderController`, menu SPA.
3. Capability **`live.view` removed**; `orders.read` / `bills.read` now need `orders.view` / `bills.view`.
4. Smaller: pickup board, insights, stats, `ReportService`, `lang/` files, `routes/api.php`, orders view, i18n.
5. New migration `2026_11_10_000100_remove_live_view_from_roles.php`: **rewrites `roles.capabilities` for every role holding `live.view`**; `down()` is empty (not reversible); roles with neither `orders.view` nor `bills.view` lose order and bill access (only logged). This breaks the "no tenant data updates without an approved plan" rule unless approved explicitly.
6. An already-shipped migration (`2026_08_23_000400_grant_live_view_...`) was edited; harmless if already applied, but note it.
7. `.github/workflows/deploy.yml` removal in the diff is only the workflow moving to the repo root.

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
5. Rollback: code rolls back with `make deploy-rollback`, **the capability rewrite does not**. Recovery means restoring the `roles` table from the step-3 backup. This is the main reason to run the impact list first.

## 7. Risks
| Risk | Mitigation |
|---|---|
| New clone missing `.env.production` or volumes | Step 2 and 6 comparison; old clone kept as rollback |
| Server tree differs from `dd1a6c6` | Step 2 clean check before anything else |
| Deploy ships feature changes by accident | Phase A deploys only the commit-identical tree |
| Irreversible roles rewrite | Section 6 B.2 impact list, backup, owner approval |
| Older POS builds vs `PENDING` status | Check `docs/coordination/` ledger; additive-only contract rule |
| Secrets exposure | SSH key lives in Doppler `xorder/prd`; the deploy key printed once in a chat session and should be rotated |

## 8. Not done
No push, no server change, no deploy, no GitHub variable change. Only read-only checks were run (`make deploy-check`, DNS lookup, local git diffs).

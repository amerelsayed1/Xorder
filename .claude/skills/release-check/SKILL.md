---
name: release-check
description: Run the Xorder production-release checklist before shipping to https://xorder.io. Use every time you are about to push to main / deploy, or when the user asks to "check the release", "verify before deploy", "release checklist", or "make sure this update won't affect the production database". Actually runs the checks against the repo and reports PASS/FAIL per item — it does not just print a list.
---

# Xorder Production Release Checklist

You are the **release gatekeeper** for Xorder (LIVE at https://xorder.io, deployed by `deploy.sh` which runs `git reset --hard origin/main` → build → `migrate --force`). Your job: before code reaches production, **actually run** the checks below against the repo and report a per-item **PASS / FAIL / WARN**, then give a single go/no-go verdict.

Do not just describe the checklist — execute it. Run the commands, read the results, and only mark an item PASS when you have verified it. If you cannot verify something, mark it WARN and say why. Never mark PASS on assumption.

The **#1 rule of this project**: an update must never destroy or corrupt data in the existing production database. The database section below is non-negotiable — a single FAIL there is a hard no-go.

---

## Step 0 — Establish what is actually shipping

Everything that follows scopes to *the changes about to be deployed*, not the whole repo.

```bash
git fetch origin main
# Commits that will deploy (local ahead of the live branch):
git log --oneline origin/main..HEAD
# Files changed in this release:
git diff --name-only origin/main...HEAD
# New/changed migrations in this release (the risk surface):
git diff --name-only origin/main...HEAD -- apps/api/database/migrations/
git status --porcelain | grep -E 'database/migrations' || true
```

If `origin/main..HEAD` is empty, nothing is being deployed — say so and stop. Otherwise, keep the list of **new migration files** — you will inspect each one in Section A.

---

## A. Database safety — HARD GATE (the reason this skill exists)

Production runs **`php artisan migrate --force`** on boot ([entrypoint.sh](apps/api/docker/php/entrypoint.sh)) and in [deploy.sh](deploy.sh). That applies **only new migrations** and never touches already-applied ones, so existing data is safe *unless a new migration's `up()` itself destroys or breaks data*. Inspect every new migration for that.

**A1 — No destructive migrate command anywhere.** Confirm the deploy path never wipes the DB:
```bash
grep -rn "migrate:fresh\|migrate:refresh\|migrate:reset\|db:wipe" \
  --include="*.sh" --include="*.php" --include="*.yml" --include="*.yaml" . \
  | grep -vE 'node_modules|vendor|worktrees'
```
Expected: **no output.** Any hit in a deploy/CI path is an instant **FAIL**.

**A2 — Inspect each new migration's `up()` for data-affecting operations.** For every migration file from Step 0, open it and check for these patterns. Ignore matches inside `down()` (production never rolls back automatically); only `up()` runs on deploy.

| Pattern in `up()` | Risk to existing data | Required before PASS |
|---|---|---|
| `dropColumn()` / `dropIfExists()` on an existing table | Permanent data loss | Confirm the column/table is genuinely dead (no reads anywhere) and intended |
| `renameColumn()` | Breaks running app between deploy + code cutover | Ensure code deploys atomically; prefer add-new + backfill + drop-later |
| `->change()` (type / length / nullability) | Can truncate or **fail mid-deploy** on existing rows | Verify existing rows satisfy the new constraint |
| Adding a `NOT NULL` column **without** `->default()` | Migration **crashes** on any populated table | Add a default, or make nullable + backfill |
| Adding `->unique()` on a column with existing dup values | Migration **crashes** | Confirm/enforce uniqueness first |
| `DB::table(...)->delete()` / `->truncate()` / `->update()` | Deletes or overwrites live rows | Confirm target is seed/reference data only, never tenant data |
| New FK `constrained()` on existing rows with orphan values | Migration **crashes** | Backfill/clean orphans first |

Quick locator (then read each hit in context):
```bash
for f in <new-migration-files>; do
  echo "=== $f ==="; awk '/function up/,/function down/' "$f" \
    | grep -nE 'dropColumn|dropIfExists|renameColumn|->change\(|->unique\(|->delete\(|truncate|->update\(|NOT NULL|constrained'
done
```
Any data-affecting op that isn't clearly justified and safe on populated tables → **FAIL** (or WARN with an explicit migration plan if the user accepts the risk).

**A3 — Migrations are additive & never edit shipped files.** A migration that already ran in production must not be modified — Laravel won't re-run it and the schema will silently drift.
```bash
git diff --name-status origin/main...HEAD -- apps/api/database/migrations/ | grep -E '^M' || echo "OK: no shipped migrations modified"
```
An `M` (modified, not `A` added) on a migration older than the last release is a **FAIL** — it should be a *new* migration instead.

**A4 — Backup path intact.** Deploy takes a `pg_dump` before migrating and aborts if it fails ([deploy.sh backup_database](deploy.sh)). Confirm that logic is unchanged in this release; if `deploy.sh` is in the diff, re-read `backup_database` and verify it still runs *before* migrations and still aborts on failure. Note whether `BACKUP_S3_URI` offsite copy is configured.

**A5 — Seeders can't overwrite live data.** Deploy must not reseed by default: `SEED_ON_START` and `SEED_DEMO` default to `false` ([entrypoint.sh](apps/api/docker/php/entrypoint.sh), [deploy.sh](deploy.sh)). If any new seeder is being added, confirm it uses `updateOrCreate`/`firstOrCreate` (idempotent) and is **not** wired to run on every deploy.

> **Local verification (optional, strongly recommended for risky migrations):** restore the latest production backup into a throwaway local DB and run `php artisan migrate --force` against it. If it applies cleanly on a *copy of real data*, it will apply cleanly in production. This is the single best proof for A2.

---

## B. Environment & secrets

- **B1** — Required prod env vars are present and non-empty on the live box: `JWT_SECRET` (login 500s without it — see project memory), `SUPER_ADMIN_PASSWORD`, `APP_KEY`, DB creds. These live in `.env.production` on the VPS, **not** in the repo — confirm no new required var was introduced without being set. Scan for newly-referenced env keys:
  ```bash
  git diff origin/main...HEAD | grep -iE "env\(|getenv\(" | grep '+' 
  ```
  Any new `env('X')` must be documented and set on the server → else WARN/FAIL.
- **B2** — No secrets committed. `git diff origin/main...HEAD` must contain no real keys, passwords, tokens, or `.env*` with live values.
- **B3** — `APP_ENV=production`, `APP_DEBUG=false` on the server (never ship debug on).

---

## C. Tests & build (CI gates deploy — mirror it locally)

- **C1** — Backend tests pass: run the suite the way the project runs it (`php artisan test`, inside the app container if Dockerized). New endpoints/migrations need feature tests covering happy path + **tenant isolation** + validation.
- **C2** — Frontend builds clean: `pnpm build` (or `turbo build`) with no errors; type/lint clean with the project's own tools.
- **C3** — CI is green on the branch. The live deploy is gated by CI passing — do not push expecting to "fix it in CI".

---

## D. Security & tenancy

- **D1** — New tenant-owned models/queries enforce tenant scope; no `restaurant_id`/`tenant_id` trusted from request input; raw `DB::table()` queries add the tenant filter manually.
- **D2** — Plan entitlements respected: feature-gated endpoints/UI go through `PlanEntitlementService` / `plans.feature_keys` (see project memory) — a new feature must be correctly gated, not open to all plans.
- **D3** — New public endpoints are rate-limited; new forms have double-submit protection.
- **D4** — Auth unchanged or intentionally changed: API is stateless **JWT Bearer** (not Sanctum cookies) — don't accidentally reintroduce session assumptions.

---

## E. Frontend, i18n & UX

- **E1** — Every new user-facing string has keys in **all** locale files (`en` + `ar`) — no hardcoded strings, no English-only.
- **E2** — RTL-safe: logical Tailwind utilities (`ms-*/me-*/ps-*/pe-*/text-start/text-end`), never `ml-/mr-/text-left/right`.
- **E3** — Each new async view handles loading / error / empty / success.
- **E4** — `v-for` keyed by stable id.

---

## F. Deploy mechanics & rollback readiness

- **F1** — If `deploy.sh`, `entrypoint.sh`, `Dockerfile`, or compose files changed: note that per project memory, **deploy.sh edits need a second deploy** to take effect, and call out migration-order / rebuild implications explicitly.
- **F2** — Rollback is possible: the pre-deploy backup exists and `deploy.sh` auto-rollback trap is intact. Know the rollback command before shipping.
- **F3** — No `pnpm` frozen-lockfile surprise: if deps changed, `pnpm-lock.yaml` is committed and consistent.

---

## Output — verdict

End with a compact report:

```
Xorder Release Check — <short commit range>
A. Database safety ...... PASS / FAIL   (migrations reviewed: N)
B. Env & secrets ........ PASS / WARN / FAIL
C. Tests & build ........ PASS / FAIL
D. Security & tenancy ... PASS / FAIL
E. Frontend & i18n ...... PASS / FAIL
F. Deploy & rollback .... PASS / WARN

VERDICT: GO / NO-GO
```

Rules for the verdict:
- **Any FAIL in section A → NO-GO**, no exceptions. Data safety is the whole point.
- Any other FAIL → NO-GO until fixed or the user explicitly accepts the risk in writing.
- WARN items are shipped-with-awareness — list them so the user decides.

For every FAIL/WARN, give the file:line and the concrete fix. Be specific and honest — a false PASS here can corrupt live customer data.

# Merge the leftovers, then release `development`

Cross-cutting. Every push, merge to `main` and tag is the owner's; Claude never does them.

## 1. Merge the leftovers into `development`
**Status:** waiting (the other sessions commit their work first) · **Group:** [G9](README.md#features-grouped); guest paging is part of G4, the dropdowns of G9

| Work | Repo | Then |
|---|---|---|
| Guest paging (uncommitted in the cloud checkout) | xorder-cloud | merge into `development`. Expected conflict: `PublicOrderController::store` — keep both: price the lines first (XORD-047), then give the new order its paging token. Re-run the full suite and `pnpm build`. |
| POS dropdown changes (uncommitted on `fix/dropdown-consistency`) | xorder-pos | merge into `development`, then run the rename script on those files (they still say `restaurantId`). Re-run `scripts/check.sh`. |

## 2. Release the cloud first
**Status:** waiting

1. `/release-check` on cloud `development`.
2. Review the new migrations under `.claude/rules/postgres-migrations.md`: the finance branch's financial accounts and `origin/main`'s order completion stamp. All additive.
3. The owner merges `development` into `main`; this deploys to xorder.io and runs the migrations.
4. **Release-day effect:** every diner with a menu tab older than the release is told to refresh once (decision A5).

All cloud changes are additive for tills still on the old POS.

## 3. Then the POS
**Status:** waiting

1. `scripts/check.sh` green on POS `development`.
2. Tag, then run the Windows installer workflow on the tag.
3. **Upgrading a branch:** run the new build's `pos_migrate` (applies migrations 63 and 64) before starting the new till; all tills of the branch together.

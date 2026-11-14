# Super Admin

The platform side: the `admin.` portal where XOrder staff create businesses, issue licences and set what each business may do.

## Done

### Content languages are Super-Admin-only
**Status:** done (cloud `development` `d5bb5cb`) · **Group:** [G3](README.md#features-grouped) · **Repo:** xorder-cloud · **Closes:** the clash between XORD-005 and main's 2026-11-03 rule

- One setting for the whole business (Arabic only, English only, or both with one primary), set on the Super Admin business form (`apps/web/src/pages/admin/RestaurantForm.vue`; `Admin/StoreRestaurantRequest`, `Admin/UpdateRestaurantRequest`).
- The business owner's Profile shows it read-only with "Set by XOrder…"; their save ignores `bilingual` and `default_language`.
- Per branch, only item availability varies; there is no per-branch language.
- Tests: `ContentLanguagesTest` (owner cannot change; staff without `settings.update` refused), full suite 1179 passed.

## Next

### Tell the tills when the Super Admin changes a business's language
**Status:** ready · **Group:** [G3](README.md#features-grouped) · **Repo:** xorder-cloud · **Approval:** none beyond the go

- **Today:** the admin business controllers never call `PosConfigVersion::bump`, so a language change reaches the tills only when something else bumps the version (UNVERIFIED how long that takes; the 4-hour idle sync at most once something does).
- **Change:** bump `pos_config_version` when `default_language` or `bilingual` actually changes on the admin update path (same pattern as the owner-side tax-number check in `Dashboard/RestaurantProfileController.php`).
- **AC:** a language change moves the version by one; saving the same values does not. **Test:** Feature test on the admin update endpoint.

### Cloud rename to "business"
**Status:** waiting (owner) · **Group:** [G8](README.md#features-grouped) · **Repo:** xorder-cloud · **Approval:** the owner, step by step (production database)

- The POS already says "business". The cloud still has `restaurants`, `restaurant_id` and `RestaurantScope` everywhere, and its API sends `restaurant` / `restaurant_id` to the tills and menus.
- **Needs first:** a written multi-step plan — additive columns or views, both names served for a while, every client moved, then removal — reviewed under `.claude/rules/production-safety.md`. Pushing to `main` runs migrations on xorder.io.
- **Blocked by:** the other session's uncommitted cloud work (guest paging, 45 files) — the rename would touch most of the same files.

## Waiting on the owner

- (G3) **XORD-055** — how fast a staff change (new cashier, PIN) must reach a running till. Today: up to 4 hours unless someone presses sync on the till. Options: tell the dashboard user, or have the till check soon after a staff change. Affects [pos-cloud.md](pos-cloud.md) too.
- (G8) **Cloud rename plan** — write it now, or after guest paging is committed.

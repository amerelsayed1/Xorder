# Recovered from the old Xorder folder

`sidebar-settings-entry.patch` is uncommitted work found in
`Xorder/apps/xorder-cloud/.claude/worktrees/sidebar-settings-entry`
(branch `fix/sidebar-settings-entry`, base `c2191fb`). Paths in the patch are
relative to `apps/xorder-cloud/` (the old repo layout).

It turned the one-item "Settings" sidebar section into a flat item, added a CSS
rule for a flat item after a section, and removed the `restaurant_settings` label.

**Status: superseded, not applied.** On `main` the Settings section has since
gained a second entry ("My plan"), so there is no longer a single-page section to
flatten, and `restaurant_settings` is still used. Applying it conflicts in
`nav.config.js` and `packages/ui/src/i18n/index.js`. Kept for reference; delete
once nobody needs it.

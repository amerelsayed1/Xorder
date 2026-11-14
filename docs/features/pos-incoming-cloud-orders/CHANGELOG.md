# Changelog — pos-incoming-cloud-orders

- 2026-11-09 — S4 (POS-BE-033) built in the cloud worktree `feat/pos-be-033-incoming-feed`: feed + accept/reject/handled, additive migration, `reject_reason` on the public order status. Not committed, not deployed. `guest-paging` S5 renumbered to POS-BE-034.
- 2026-11-09 — review fixes: visit orders excluded, cursor validated, `reject_reason` not public (`rejected: true` instead), migration guards removed and feed indexes extended with `id`.

# API — pos-terminal-delete-visibility

| Endpoint | Change |
|---|---|
| `GET api/dashboard/pos/terminals` | each item adds `has_money_history: boolean` |
| `GET api/admin/restaurants/{restaurant}/terminals` | same |

Additive. Other responses built from `PosTerminalResource` (provision, show, fleet) do not include the field. `DELETE` endpoints unchanged: `422 TERMINAL_STILL_ACTIVE`, `422 TERMINAL_HAS_HISTORY`. The POS does not call these endpoints.

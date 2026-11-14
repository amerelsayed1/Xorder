# Database — pos-terminal-delete-visibility

No schema change and no migration. The list query adds `EXISTS` subqueries over `pos_shifts.pos_terminal_id` and `orders.pos_terminal_id` (both foreign keys). Neither column has an index of its own: PostgreSQL does not index foreign keys automatically, and the only `pos_shifts` index is `(restaurant_id, pos_terminal_id, status)`. An additive index is proposed and waits for the owner (XORD-042).

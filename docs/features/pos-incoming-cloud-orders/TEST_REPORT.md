# Test report — pos-incoming-cloud-orders (S4, POS-BE-033)

2026-11-09 · cloud worktree `feat/pos-be-033-incoming-feed` (base `775bf0f`, uncommitted) · SQLite `:memory:`

| Command (from `apps/xorder-cloud/.claude/worktrees/pos-be-033/apps/api`, with a throwaway `APP_KEY`) | Result |
|---|---|
| `php artisan test --filter PosIncoming` | 16/16 passed (before review fixes), 3 consecutive runs |
| `php -d memory_limit=-1 vendor/bin/phpunit` (full suite; `php artisan test` hit the 128 MB default limit) | **1165 passed**, 5737 assertions, 0 failed (includes 17 new `PosIncomingTest` tests) |

Covered: first read, each event once, same-second changes, 304 on idle, terminal states reach other tills, switch off, `last_feed_at`/`app_version`, bad cursor (garbage and crafted `ts`), cross-tenant and cross-branch 404, POS/WhatsApp orders excluded, open-visit orders excluded, accept idempotent + second till 409, reject + diner status flag, completed order 409, handled once, validation, revoked terminal, unchanged status reply.

**Not proven:** `lockForUpdate` (a no-op on SQLite; the two-till race is serial), PostgreSQL lock/index behaviour (read by `database-reviewer`, never run), AC-1 latency (needs S7), AC-5 (permission not built), AC-16 (screens). Migration never run on a real database. Nothing in the POS repo was changed or tested.

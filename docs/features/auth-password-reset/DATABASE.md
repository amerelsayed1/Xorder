# Database impact: Password reset by email

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Tables and constraints
| Table.column | Detail | Migration |
| --- | --- | --- |
| `password_reset_tokens` | `email` primary key, `token` string, `created_at` nullable timestamp | `C:database/migrations/0001_01_01_000000_create_users_table.php:28-32` |
| `users.email` | string, unique, later nullable | `:17`; `C:database/migrations/2026_07_21_000200_add_username_to_users_table.php:40` |
| `users.password`, `password_changed_at`, `remember_token` | written by a successful reset | `PasswordResetController.php:40-46` |

## Relationships
The broker matches `password_reset_tokens.email` to `users.email`.

## Shared entities across applications
None.

## Proposed changes
None (as-built documentation).

## Transactions and concurrency
No explicit transaction in the controller; the broker's behavior is vendor code (not read).

## Indexes and query performance
Primary key on `password_reset_tokens.email`; unique `users.email`.

## PostgreSQL vs SQLite differences
None found for this feature.

## Migration and rollback plan
No change proposed.

## Backup/data access constraints
Token rows contain hashed reset tokens and emails; no backup content was read.

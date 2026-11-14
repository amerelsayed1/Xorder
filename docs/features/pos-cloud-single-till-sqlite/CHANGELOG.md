# Changelog — pos-cloud-single-till-sqlite

## 2026-11-09 — built (xorder-pos `development`, not pushed)
- **The Cloud app keeps each till's data in one encrypted SQLite file** (SQLite3MultipleCiphers in SQLCipher mode, key in the OS secret store). No PostgreSQL on a cloud till: setup prepares the file itself, with no database screen.
- Every cloud till stands alone (owner decision Q8): no tablets on another till's database; setup and the floor say each till keeps its own tables and checks.
- One set of repositories for both engines through `lib/data/sql/`; PostgreSQL SQL unchanged for the Offline app.
- Schema generated from PostgreSQL migration 64; triggers and pattern checks hand-translated; a new PostgreSQL migration on a cloud-till table must add a SQLite counterpart.
- Day-close backup on a cloud till is a verified encrypted copy of the file; a hard reset keeps the data key.
- Windows Cloud installer ships no PostgreSQL.
- `scripts/check.sh` also runs the cloud-till suites on SQLite.

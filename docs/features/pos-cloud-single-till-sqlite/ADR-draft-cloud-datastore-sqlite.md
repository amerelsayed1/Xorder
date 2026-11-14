# ADR (draft): the cloud app keeps its data in an encrypted SQLite file

Status: **accepted by the owner 2026-11-08**. Drafted in the workspace, because repo `docs/` is not written by the harness; to be placed as `apps/xorder-pos/docs/pos/adr/ADR-0xx-cloud-datastore-sqlite.md` by the owner.

## Context
- `docs/pos/08-postgres-lan.md` decided **PostgreSQL in every mode**. A cloud till therefore runs a PostgreSQL server of its own, installed by the Windows installer and missing entirely on macOS.
- Since pos-split-apps there are two apps: cloud and offline. A cloud till's data is a cache of the platform plus its own unsent sales.

## Decision
- **XOrder POS - Cloud** keeps its local data in **one encrypted SQLite file per till** (`sqlite3` package, SQLite3MultipleCiphers build in SQLCipher-compatible mode, 32-byte key in the till's secret store).
- **XOrder POS - Offline** keeps PostgreSQL, unchanged.
- **Every cloud till stands alone** (owner, Q8): no shared database on the LAN, and no cloud tablets on the main device's database. Tills in one venue meet only through the platform (finished orders, shifts, refunds, customers).
- **One set of repositories runs on both engines** through a small SQL seam (`packages/shared_module/lib/data/sql/`), with portable SQL. The schema is kept twice (PostgreSQL migrations; SQLite schema list).

## Consequences
- No PostgreSQL on a cloud till: a simpler install, and nothing to run on macOS.
- Several cloud tills in one restaurant do not see each other's open tables or parked checks. Two can seat the same table. Setup and the floor say so. Shared tables via the platform is a later feature.
- Every future migration on a table a cloud till uses is written for both engines.
- On macOS the key sits with the user account. The encryption protects a copied file or a stolen disk, not a logged-in user.

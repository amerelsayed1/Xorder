# 18 — The Windows installer

Readiness item 10. One installer a technician runs on a clean Windows 10/11 x64
machine; the same installer run again upgrades in place.

## What it installs

The installer offers two types. It follows the owner's decision of 2026-09-11 —
bundle PostgreSQL. That supersedes 08-postgres-lan §5, which kept PostgreSQL off
the till.

| Type | Installs | Does |
|---|---|---|
| **This machine keeps the database** | the app, PostgreSQL 16 (EDB binaries), `pos_migrate.exe` | creates the database, its three accounts and its service, then migrates |
| **Till only** | the app | nothing else; the setup wizard connects it to the machine above |

Everything lands under `C:\Program Files\XOrder POS\`:

- `xorder_pos.exe`: the app, branded *XOrder POS*.
- `pgsql\`: PostgreSQL. The Backup screen finds `pg_dump` here before looking
  anywhere else, so it always uses the version that matches the server.
- `tools\pos_migrate.exe`, `tools\provision.ps1`: provisioning.

Data lives in `C:\ProgramData\XOrder POS\`:

- `pgdata\`: the database. Only Administrators, SYSTEM and the service account
  can open it.
- `install-credentials.json`: the four passwords (`postgres`, `pos_admin`,
  `pos_till`, `pos_backup`) and the port. Administrators and SYSTEM only. The
  setup wizard asks for the till's password and the back office's; the Backup
  screen asks for the backup account's.
- `logs\provision.log`: what setup did. Passwords never appear in it.

## What provisioning does (`installer/provision.ps1`)

It is safe to run again, and running it again is the upgrade. Every step checks
first.

1. **Passwords.** On a fresh install it generates four 24-character passwords
   from the OS's cryptographic generator, and writes and locks the credentials
   file *before* anything can fail.
2. **`initdb`.** It uses `-A scram-sha-256`: never `trust`, not even for
   localhost. Encoding is UTF-8.
3. **Configuration.** Port 5432, or the next free one up to 5442 if something
   else is listening. It listens on `localhost` by default. The **"Let other
   tills on this network use this database"** option opens it to the private
   ranges only (10/8, 172.16/12, 192.168/16), still with a password, and adds a
   firewall rule for the Private and Domain profiles. Turning the option off on a
   later run takes both away again.
4. **Service.** `XOrderPOS-PostgreSQL`, automatic start, running as
   NetworkService. Permissions are set by security ID, never by name, so an
   Arabic-language Windows behaves the same.
5. **Accounts and database** (`pos_migrate --create-roles --create-database
   --owner pos_admin --no-migrate`, as the superuser):
   - `pos_admin`: login and CREATEDB, nothing more.
   - `pos_till`: login only.
   - `pos_backup`: login plus `pg_read_all_data`.
   - `xorder_pos`, owned by `pos_admin`.

   Existing accounts are left alone, passwords included.
6. **Migrations and grants** (`pos_migrate --grant-to pos_till`, as
   `pos_admin`). Every table is therefore `pos_admin`'s, which is what lets a
   restore replace them.

All the database logic is in `pos_migrate`. `test/data/install_provisioning_test.dart`
tests it against a real server on every database-suite run, through the CLI
exactly as the script calls it. `test/tool/installer_consistency_test.dart`
keeps the three installer files in agreement: flags, paths, service name, the
upgrade id, passwords through the environment only, and SIDs not names.

## Upgrade and uninstall

- **Upgrade.** Run the newer installer. The same `AppId` makes it an in-place
  upgrade. The database service is stopped before files are replaced, then
  `provision.ps1` applies the new migrations and starts it.
- **Uninstall.** Removes the app and the service. **The data stays** in
  `C:\ProgramData\XOrder POS\`; a trading history is not the uninstaller's to
  delete.

## Building it

`.github/workflows/windows-installer.yml` runs on a `v*` tag, or by hand:

1. Builds the app with Flutter 3.47.0 and compiles `pos_migrate.exe`.
2. Downloads PostgreSQL `PG_VERSION` and prints its SHA-256. Pin `PG_SHA256` to
   that value after the first build.
3. Bundles the VC++ runtime and compiles the installer with Inno Setup.
4. **Installs it on the runner.** Checks the service is running, no migration is
   pending, the tables are `pos_admin`'s, and the backup account can read. Then
   it writes a marker row, **runs the same installer again as an upgrade**, and
   checks the marker is still there and nothing is pending.
5. Uploads the installer. On a tag, it attaches it to a GitHub release.

The tag must equal `pubspec.yaml`'s version (`v1.2.0` ↔ `version: 1.2.0+…`).

**Signing.** Add the repository secrets `WINDOWS_CERT_PFX_BASE64` (the
code-signing certificate, base64) and `WINDOWS_CERT_PASSWORD`. The app, the
tool, the installer and the uninstaller are then signed with a timestamp.
Without them the build is unsigned and SmartScreen warns on every machine.

## Not done yet

- **Never run on real Windows.** Nothing Windows-side has run yet; the first CI
  run is the first time. Expect fixes from it.
- **No certificate.** The build is unsigned until one exists.
- **The wizard does not pre-fill.** The technician copies passwords from
  `install-credentials.json`. Reading that handoff into the wizard is the next
  step.
- **No major-version upgrade.** PostgreSQL 16 → 17 needs `pg_upgrade`, and the
  installer does not attempt it. Minor updates (16.x) are file replacements and
  work.

# Gaps, risks and open questions

Consolidated from the topic documents (each finding there carries file:line evidence; IDs below point to them).
All evidence is **[CODE]** (static reading); nothing was executed. Backend/cloud/Vue behaviour is **UNKNOWN**.

## 1. Plan A / Plan B requirement gap matrix

| Requirement | Plan | Status | Gap (evidence in) |
|---|---|---|---|
| POS operates locally without internet | A, B | IMPLEMENTED | Sale commits to local PostgreSQL first (DATABASE_AND_SYNC §7) |
| Local transactions synchronised to cloud | A | PARTIAL | Orders, shifts, cash movements, refunds, customers upload; **stock, purchasing, voided orders do not** (DATABASE_AND_SYNC §0, §5) |
| Cloud authoritative on conflict | A | PARTIAL / not defined | Only *configuration* is cloud-authoritative (bootstrap wipe-and-reseed of catalogue). No transactional conflict resolution exists; server error codes are only classified; 6 codes quarantine, everything else retries forever; quarantined rows have no release path (DATABASE_AND_SYNC §5, §10) |
| Pending local sales protected from cloud overwrite | A | IMPLEMENTED for orders/outbox/shifts/refunds | Bootstrap never touches them. Risk: a catalogue `DELETE` can fail on FK for stocked products and is swallowed → stale menu (D9) |
| Completely local restaurant management | B | PARTIAL | Menu/staff/inventory/purchasing admin exists in-app; no BOM, stocktake, waste, adjustments (FEATURE_INVENTORY_ADMIN) |
| Multiple POS on restaurant LAN | B (and A) | PARTIAL | Shared PostgreSQL, no API, manual host entry, no discovery, one shared DB role, no failover, LAN TLS off by default (MULTI_DEVICE) |
| Automatic local backups | B | PARTIAL | Only after day-close (default on) or manual; same disk; no clock schedule; unencrypted; no off-box copy (OPERATING_MODELS Q10, SECURITY §10) |
| Offline licence activation/renewal by signed file or key | B | **PARTIAL (file) / NOT_IMPLEMENTED (key, renewal)** | Verifier + CLI issuer exist, but **no UI imports a `.xlic`**; typed key is exchanged online (LICENSING) |
| No operational cloud sync | B | IMPLEMENTED | Offline mode builds no cloud client and enqueues nothing |
| Switching plans | A↔B | NOT_IMPLEMENTED | Only Reset + wizard; cloud→offline strands unsent outbox rows and hides the count; offline→cloud does not backfill (OPERATING_MODELS Q4) |
| Licence decides operating model | A, B | PARTIAL | Licence `modes[]` restricts which wizard tiles are offered and vetoes opening a shift; the chosen mode is stored in `config.json` (LICENSING, OPERATING_MODELS Q2-3) |
| Device limit by licence | A, B | PARTIAL | `max_terminals` checked only in child-registration wizard by counting `pos_terminals` rows; no DB constraint, no runtime check, no retire path (MULTI_DEVICE §7) |
| Arabic default, switch in General Settings | UX | PARTIAL | Default is Arabic; switch exists in 3 other places but no screen called General Settings is the home; wizard language step only applies at `complete()`; bar toggle may be overwritten by draft (CURRENT_SETUP_WIZARD) |

## 2. Critical risk register (top items; full list: SECURITY_AND_RECOVERY §15, DATABASE_AND_SYNC §10)

| ID | Category | Risk | Severity |
|---|---|---|---|
| R-DATA-1 | Data loss | Restoring an older backup silently discards sales not yet uploaded; restore only blocks on open shift/business day, not on pending outbox rows (DATABASE_AND_SYNC D3) | High |
| R-DATA-2 | Data loss/dup | A 2xx reply with a non-JSON body (e.g. captive portal) marks an order as delivered (D4) | High |
| R-DATA-3 | Availability | Held/quarantined outbox rows (unknown menu item, unknown tender) have no release path and stay in the pending count forever (D1/D2) | High |
| R-DATA-4 | Data | No lease/backoff/attempt cap on outbox; a crash mid-send re-sends with the same key (safe only if the server dedups on that key — UNKNOWN) | Medium |
| R-DATA-5 | Data | Stock never syncs; refunds/voids do not restock; no recipes → sales and stock can drift (FEATURE_INVENTORY_ADMIN) | Medium |
| R-DATA-6 | Data | Backups live on the same disk as the database, automatic only at day close, unencrypted | High |
| R-DUP-1 | Duplication | Re-running offline wizard re-inserts `pos_terminals` rows (and consumes the device-limit count) | Medium |
| R-SEC-1 | Security | DB password, cloud device token, `pos_admin` and `pos_backup` passwords in plaintext `secrets.json`; no Windows ACL step; comments claim a keystore | High |
| R-SEC-2 | Security | 4-digit PINs (PBKDF2 120k) readable by the shared `pos_till` role → offline-crackable; cashier lock screen has no lockout; no idle auto-lock found | High |
| R-SEC-3 | Security | LAN PostgreSQL traffic plaintext by default (installer never sets `ssl=on`); one shared DB role for all tills; `terminal_id` client-asserted | High |
| R-SEC-4 | Security | Permissions are enforced in Dart on writes only; all Admin-Mode users share one DB credential; reads/export/terminal reset are UI-gated only | Medium |
| R-SEC-5 | Security | Licence: unsigned `licence_check.json` verdict cache can be edited to defeat suspension; clock rollback extends expired file licences; non-release builds trust an unsigned `issuer_public_key` in the licence file; fingerprint is a copyable random UUID | Medium (commercial) |
| R-SEC-6 | Security | Audit log: append-only by grant/trigger, but owner can drop trigger; restore replaces the table; no hash chain | Medium |
| R-AVAIL-1 | Availability | DB host down ⇒ no sales, no parking; no local fallback store, no failover | High (multi-till) |
| R-AVAIL-2 | Availability | Parked tables last-writer-wins, loaded once without refresh; settling a ticket deletes whatever is parked on that table | Medium |
| R-AVAIL-3 | Availability | Possible: an exception in the drain stops the auto-reschedule timer ([CODE], unconfirmed) | Medium |
| R-OPS-1 | Operations | No crash reporting, telemetry, log file, diagnostics screen, or support bundle; no update mechanism; no CI test gate | Medium |
| R-OPS-2 | Operations | App never runs migrations at launch; only wizard/claim/CLI/installer — an app upgrade against an older DB relies on those paths | Medium |

## 3. Documentation vs. code conflicts (do not rely on the docs for these)

See CURRENT_ARCHITECTURE §6 for the table (modes count, keystore claims, fingerprint, `hostssl`, wizard language timing,
cloud back office, licence server URL editability).

## 4. Not verifiable here (UNKNOWN)

* Everything server-side: `/api/pos/*` semantics (duplicate-key handling, price/total mismatch handling, unknown items),
  licence issuance/revocation, device token revocation, pairing, platform reporting, the Vue admin panel.
* Runtime behaviour: no test was executed; DB pool recovery after a PostgreSQL restart; behaviour of other tills after one
  restores a backup; macOS DB provisioning in practice; Android/iOS child-tablet UX; real printer behaviour.
* Dependency advisories; secrets entropy scan.

## 5. Questions for the Product Owner

**Operating model**
1. Must Plan B work with *no internet at all*, ever (air-gapped), including first activation? If yes, the offline
   activation/renewal flow (file import UI, request/response code) is net-new work.
2. Is a maximum offline period (`max_offline_days`) required in Plan A? In Plan B?
3. Is in-place switching between plans required? What must happen to unsent and historical sales?
4. Must the licence *select* the plan, or only *permit* plans (today: permits)?
5. Should "Cloud authoritative" apply to configuration only (today) or also to transactional data? Define, per entity
   (order, payment, refund, shift, stock movement, price, customer), who wins and what is audited when values differ.
   Confirm that pending local sales are never discarded.
6. Cloud-mode back office: is "tills have no back office, use the dashboard" intended (`router.dart:138-160`)?

**Data & sync**
7. Should voids and stock movements sync to the cloud? Who owns inventory in Plan A?
8. Who clears quarantined/held sync rows, and how (UI? support tool)? What should the cashier/manager see?
9. How must the server behave on duplicate keys, price/total mismatch, unknown items? (needs backend owner)
10. Is more than one cloud-mode till on one shared database officially supported (only the main device syncs)?

**Multi-device & availability**
11. Is failover/standby required if the server PC fails? What is the acceptable downtime per outage?
12. Must tables be exclusive to one till? Is live cross-till refresh required?
13. Is per-till DB credentialing or an API layer required, or is a shared role acceptable?
14. Should retired terminals free their licence seat? Should `max_terminals` also bind main devices and cloud mode?

**Backup & recovery**
15. Is an off-box, scheduled, encrypted backup mandatory for Plan B? Who is responsible for the destination?
16. Should restore be refused/warned when unsent sales exist?

**Security**
17. Is plaintext `secrets.json` acceptable, or must the OS credential store (DPAPI/Keychain) be used? Should the admin password be persisted at all?
18. Required PIN length and lockout policy; cashier idle auto-lock?
19. Must LAN database traffic be encrypted by default?
20. Is crash/diagnostic capture (log file, support bundle) required? Any privacy limits?

**Licensing**
21. Does production issue licences from the platform or via the CLI? Is the `features`/`branch_ids`/`max_users` entitlement set meant to be enforced?
22. How strongly must licences resist tampering (clock rollback, copied `config.json`)?

**UX / localisation**
23. Where exactly is "General Settings" (screen/menu) and should language also be chosen on the welcome/first wizard screen?
24. Arabic-Indic or Western digits (today Western only)? Receipt language rules?
25. Should the offline wizard read the installer's credentials file (today only the cloud path does)?

## 6. Recommended discussion order

1. **Define the data-authority policy** (Q5, Q7–Q9): it determines sync design, conflict handling and what "cloud authoritative" is allowed to touch.
2. **Plan B offline licence & renewal** (Q1–Q2, Q21–Q22): net-new flow, blocks Plan B go-to-market.
3. **Backup/restore & recovery policy** (Q15–Q16, R-DATA-1/6): data-loss exposure.
4. **Server/DB availability and LAN security** (Q11–Q14, Q19, R-AVAIL-1, R-SEC-3).
5. **Secrets and PIN/permission model** (Q17–Q18, R-SEC-1/2/4).
6. **Plan switching & device lifecycle** (Q3, Q14, R-DUP-1).
7. **Outbox operations tooling** (Q8, R-DATA-2/3/4): visibility and release path for stuck rows.
8. **Inventory scope** (Q7, R-DATA-5).
9. **UX/localisation decisions** (Q23–Q25) and diagnostics (Q20).

## 7. Addendum — sales-floor gaps and questions (from FEATURE_INVENTORY.md Part 1)

| ID | Gap / risk | Status |
|---|---|---|
| R-SALE-1 | Shift id captured with `ref.read` at provider build and not invalidated on shift open/close → sales/refunds may carry stale or NULL shift id and drop out of Z report / expected cash (runtime unverified) | Suspected defect |
| R-SALE-2 | Parked tickets restored after restart lose tax mode, tax groups, service charges and customer; `TaxConfig ==` ignores those fields | Suspected defect |
| R-SALE-3 | `TicketEngine.setLineNote` drops a line's combo / free-allowance snapshot | Suspected defect |
| R-SALE-4 | Business day is never opened by the app (no caller of `BusinessDayRepository.open`); the day-close blocker for unpaid orders is always 0 | Gap |
| R-SALE-5 | No persisted open-order lifecycle: abandoned/cleared unsent tickets leave no record (audit/loss-prevention gap) | Gap |
| R-SALE-6 | Order upload carries no customer reference; sale-to-customer link stays local | Gap |
| R-SALE-7 | Refunds and voids do not restock; no recipes → inventory drift | Gap |

Further product-owner questions:
26. Is a kitchen ticket / KDS / per-station routing required? (Today: not implemented.)
27. Is delivery (driver, zone, fee, status) in scope? Are merge / transfer / split-bill required?
28. Should the business day open automatically (or on first shift)?
29. Where do named discounts come from (no in-app writer today)? Who may author price overrides?
30. Is ETA e-invoicing signing/submission meant to live in this repo? Should card/wallet payments integrate with a terminal?
31. Should refunds restore stock? Is recipe/BOM-based inventory in v1?

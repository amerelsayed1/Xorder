---
paths:
  - "apps/xorder-cloud/apps/api/app/Services/LicenceIssuer.php"
  - "apps/xorder-cloud/apps/api/app/Services/LicenceActivator.php"
  - "apps/xorder-cloud/apps/api/app/Http/Controllers/Admin/LicenceController.php"
  - "apps/xorder-cloud/apps/api/app/Http/Controllers/Pos/LicenceController.php"
  - "apps/xorder-cloud/apps/api/app/Http/Requests/Admin/*Licence*"
  - "apps/xorder-cloud/apps/api/app/Models/PosLicence.php"
  - "apps/xorder-cloud/apps/web/src/pages/admin/pos/**"
  - "apps/xorder-pos/lib/features/licensing/**"
---

# POS licences: renewal is the edit and upgrade path (owner decision 2026-10-25)

Recorded from the owner's instruction on `/pos/licences/<id>`: *"when you renew the licence you can edit everything, so it can be upgraded."* It resolves QA item XORD-009.

- **There is no in-place edit and none is to be added.** The signed `payload` and `signature` are the record of what the customer was sold, and an installed till verifies its own copy offline. So every change to what is sold goes through `POST /api/admin/pos/licences/{licence}/renew`, which signs the new terms on a NEW row, sets `superseded_by_id` on the old one and leaves it untouched ("what were they entitled to in March?"). Do not add `PUT`/`PATCH licences/{licence}` without the owner's approval.
- **A renewal may change everything the licence's kind lets an operator choose.** Both kinds: start date, expiry or `lifetime`, `grace_days`, `warn_days`, `max_terminals`, `max_users`, `max_offline_days`, device `fingerprints`, contact details, notes. Cloud only: `plan_id`, `features`, `modes`, `branch_ids`. Offline only: the business name (`customer_name`). The form (`LicenceDetails.vue`) starts from the current values and lists what the renewal changes.
- **An offline licence never chooses features, modes, plan or branches.** It gets the whole product, offline tills only (`StoreOfflineLicenceRequest`); what it sells is capacity. `RenewLicenceRequest` does not accept those fields for `kind = offline`.
- **Never changeable by renewal:** `restaurant_id`, `kind`, `customer_slug`, `licence_ref`, the key (unless `rotate_key`), and `enforcement`. Moving any of them is a transfer and is a new issuance.
- **A key left out inherits; a key sent as `null` clears** for the fields where blank means something (`plan_id`, `max_users`, `max_offline_days`, contact fields, `notes`). That is how an upgrade to "unlimited users" is expressed; do not "simplify" `LicenceIssuer::attributes()` back to `??`.
- **Only the licence in force can be renewed.** A revoked licence or one already superseded answers 422 `LICENCE_NOT_LIVE`. Renewing a superseded row would fork two live licences under one key.
- **Audit.** `pos_licence.renewed` records `changes` (from/to) for commercial fields and `changed_private` (names only) for contact details, notes and fingerprints. Never put those values, an activation key or its hash in an audit row.
- **Propagation is honest, not instant.** The activation key is kept, so tills receive the new terms by re-fetching under it; there is no automatic pull, and an `enforcement = offline` licence never checks in. Changing `fingerprints` re-pins every till, so the screen warns before it is sent.
- **Tests:** `tests/Feature/Admin/LicenceRenewalUpgradeTest.php` pins all of the above; keep it green and extend it when a field is added. Cloud suites run on SQLite and cannot prove PostgreSQL behaviour.
- **A local licence's device count is held at activation (owner decision 2026-10-25: "it is for 1 device only").** `LicenceActivator::activate()` counts the distinct devices recorded for the key (`pos_licence_activations`, keyed on the key's HMAC so renewals share it) and refuses a NEW device with `409 licence_seats_full` once `max_terminals` are in use. A device already recorded is always let back in (renewals reach a till by re-fetching under the same key), and a downgrade never locks out a device already in. The count and the insert are one locked step. If the ledger cannot be read the till is still licensed (fail open, logged).
- **Cloud licences are NOT counted.** Their tills share one key by design and their `max_terminals` has never been enforced; turning it on would start refusing working tills. That is a separate owner decision.
- **Freeing a seat:** `DELETE /api/admin/pos/licences/{licence}/activations/{activation}` (audited `pos_licence.device_released`); it is bookkeeping, not revocation, and the device keeps its file. The stronger control is the licence's locked `fingerprints` list, which the till itself verifies; the platform count trusts a fingerprint the till reports.
- **The till must say why.** POS maps `409 + licence_seats_full` to `LicenceSeatsFull` (its own sentence in both languages); keep that in step with the code, and never reuse 403/`LicenceRevoked` for it.


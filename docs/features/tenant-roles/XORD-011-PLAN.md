# XORD-011 — Custom roles and permissions: plan for approval

Status: **PLAN ONLY. Nothing is implemented.** Prepared 2026-10-25 from the QA backlog (`XORDER_QA_FINDINGS_README.md`) and the owner's brief for XORD-011. It touches authorization and rewrites role data in production, so `CLAUDE.md` requires approval before any code or migration.

Verification legend: **VERIFIED** = read in source on 2026-10-25. **UNVERIFIED** = not confirmed; do not rely on it.

## 1. The requirement, and where each part stands today

| # | Requirement | Cloud (`xorder-cloud`) | POS (`xorder-pos`) |
|---|---|---|---|
| 1 | Do not auto-generate business roles | **Mostly met.** Only one role is seeded per restaurant, `Admin` (`TenantRoleService::seedSystemRoles`, called from `RestaurantProvisioningService.php:129`). The migration `2026_08_23_000200` already removed the four older presets. VERIFIED | **Not met.** `SystemRoles.seeded` writes Owner, Manager, Supervisor and Cashier at install (`local_bootstrap.dart:395`, `pos_migrate.dart`). VERIFIED |
| 2 | Predefined permission catalogue | **Met.** `TenantCapability` is the catalogue; roles can only hold its values (`Role::capabilityValues`). VERIFIED | **Met.** `PosCapability.all`, classified by risk, grouped for the role editor. VERIFIED |
| 3 | A role can be assigned to many employees | **Met.** `users.role_id` is many-to-one. VERIFIED | **Met.** `pos_staff.role_id`, plus extra roles per person. VERIFIED (extra roles from the earlier analysis) |
| 4 | Roles and their permissions can be updated | **Met.** `TenantRoleService::update`, with the "cannot grant above yourself" intersection. VERIFIED | **Met.** Roles pane; the owner role must keep every capability. VERIFIED |
| 5 | Unsafe deletion is prevented | **Partly.** A role with holders is refused unless the caller names a `reassign_to` role; `is_system` roles are undeletable (`RoleController::destroy`). It counts all holders, active or not. VERIFIED. What the FK does to `users.role_id` on delete is UNVERIFIED | **Met.** `RoleStillHeld` refuses deletion while held; system roles are undeletable (`postgres_admin_repositories.dart:295-310`). VERIFIED |
| 6 | Existing staff assignments survive migration | Nothing to migrate unless we change Admin (see 3.1) | Needs care: migrations 46, 47, 48 and 53 key on `code = 'owner'` |
| 7 | The verified owner keeps authority without a generated Owner role | **Met.** The owner is a `RESTAURANT_ADMIN` account; `User::holdsTenantCapability` returns true for every capability and does not look at `roles`. VERIFIED | **Not met.** Ownership **is** the `owner` role: 11 code sites test `role.code == 'owner'` (`admin_session.dart:342`, `authorization.dart:366`, five in `postgres_admin_repositories.dart`, `setup_controller.dart:801`, `bin/pos_migrate.dart:294`). VERIFIED |

**Conclusion.** The cloud already satisfies most of XORD-011. The real work is the POS, where "the owner" is a role and four roles are generated. That is also where the risk is.

## 2. Open owner decision this depends on: CB-06

`docs/coordination/BACKOFFICE_TO_CLOUD.md` CB-06 asks whether roles on a **cloud** till are authored on the platform or stay till-local. It is unanswered. XORD-011 on the POS means different things in each case:

- **(b) platform-only roles on cloud:** the till's Roles pane becomes read-only on cloud tills, and a cloud till has no role generation question at all.
- **(a) till-local roles on cloud:** the POS rules below apply to cloud tills too, and the bundle must tell the till who the owner is.

Recommendation: answer CB-06 as (b) for cloud, since the platform already owns users, roles and the owner. That keeps this plan to **offline installs** on the POS and **new-restaurant provisioning** on the cloud.

## 3. Proposed design

### 3.1 Cloud (small, additive)

1. **Stop seeding `Admin` for newly provisioned restaurants.** The owner needs no role, and every other role is the owner's to create. Effect: a new restaurant must create its first role before adding staff. The staff form already requires `role_id`.
2. **Existing restaurants keep their `Admin` role and its holders untouched.** Whether to also flip `is_system` to false so an unused `Admin` becomes deletable is **your call** (3.3, question 2). If yes, it is a one-line data update in the style of `2026_08_23_000200`, run in a normal deploy.
3. **Deletion rule.** Decide between "block while any active holder" and today's "allow with `reassign_to`" (question 3). Either way, check what `users.role_id` does on delete before relying on it.
4. **Tests to add** (`TenantRbacTest` neighbourhood): a new restaurant has no roles; its owner can still do everything; the owner can create a role, assign it to two employees, edit it, and cannot delete it while active holders exist; the above holds across tenants (404, never 403).

No new endpoint, no response-shape change, no bundle change.

### 3.2 POS (expand, switch, contract; offline installs)

The owner stops being a role and becomes a flag on the person.

**Phase A: expand (additive, safe to ship alone).**
- New column `pos_staff.is_owner boolean NOT NULL DEFAULT false`, with a partial unique index `(restaurant_id) WHERE is_owner AND is_active`. This is the one-active-owner rule the code enforces today, moved into the schema.
- Backfill: `is_owner = true` for staff whose role has `code = 'owner'`. **Their `role_id` is left exactly as it is.** Preserves requirement 6.
- Code reads `is_owner OR role.code = 'owner'`. Nothing changes behaviour yet.

**Phase B: switch.**
- `Authorization.check` and `PosStaff.can`: `is_owner` ⇒ allowed for every capability. The "owner role must hold every capability" check in `RolesRepository.save` is retired.
- Replace the 11 `role.code == 'owner'` tests with `staff.isOwner`. Keep the existing rules: one active owner, the owner's access and PIN are not editable by others, ownership moves only by disabling the owner first.
- Installer, `bin/pos_migrate.dart` and the setup wizard create the owner person with `is_owner = true` and **no role**. Requires `pos_staff.role_id` to be nullable. UNVERIFIED; check before Phase A.

**Phase C: stop generating.**
- `seedSystemRoles` no longer inserts Owner, Manager, Supervisor or Cashier. The role editor's **templates** (`SystemRoles.templates`) stay: they are starting points the owner chooses, not roles created behind their back.
- Existing seeded roles keep working and keep their holders. A data update sets their `is_system` to false so unused ones become deletable (same precedent as cloud `2026_08_23_000200`).
- The migrations that key on `code = 'owner'` (46, 47, 48, 53) are shipped history; **do not edit them**. A new migration supersedes their intent.

**Phase D: contract (later release).** Remove the `OR role.code = 'owner'` fallback after every install has run Phase A, which the migrator guarantees on next start.

### 3.3 Decisions I need from you

1. **CB-06:** platform-only roles on cloud tills (recommended), or till-local?
2. **Cloud `Admin` role:** keep it undeletable on existing restaurants, or make it deletable once nobody holds it?
3. **Deletion:** refuse while any active employee holds the role (strict), or allow with an explicit `reassign_to` as today?
4. **POS owner flag:** approve `pos_staff.is_owner` replacing the Owner role, with the unique index?
5. **Roles after Phase C on a brand-new offline install:** the owner starts with no other roles and creates them from templates. Is an empty Roles list acceptable for a café on day one, or should the setup wizard offer to create roles from templates as an explicit step? (Offering is not generating: the owner chooses.)
6. **"Verified business owner":** I read this as the account the platform provisioned (cloud) or the person the installer created (POS). Is there a verification step I have not seen?

## 4. Impact analysis

- **Venue models.** Cafés and food trucks (one owner, one or two staff, often unreliable power and signal) lose most from an empty start; restaurants and cloud kitchens (many roles) lose least. Question 5 exists for them.
- **Money and order integrity.** No ticket, tender, refund or shift logic changes. What changes is who passes `Authorization.check`; a mistake here widens or removes access, so the owner path is covered by tests before any seeding is removed.
- **Security.** Highest risk: the owner flag becomes the root of trust on the till. Failure mode to avoid: an install with **no active owner** after migration (backfill finds no `owner` role holder). Phase A must report such installs and leave their behaviour unchanged rather than guess.
- **Independent deploys.** Cloud and POS ship separately and the plan needs no new contract field if question 1 is (b). If it is (a), the bundle needs an additive `staff[].is_owner` and the POS seeder must tolerate its absence (older cloud).
- **Rollback.** Phases A to C are additive or flag flips; reverting the code leaves a harmless column and unprotected roles. Nothing is dropped.

## 5. Test plan

Cloud: the four tests in 3.1. POS: Phase A backfill (owner found, none found, two found), partial unique index refuses a second active owner, owner passes every capability with no role, a non-owner with the same role does not, installer creates a role-less owner, seeding creates no roles, existing seeded roles stay held and become deletable only when unheld, and the migration is idempotent. PostgreSQL-backed suites run only against the fixture database.

## 6. Files that will change (not yet touched)

Cloud: `app/Services/TenantRoleService.php`, `RoleController.php` (if question 3 changes the rule), one data migration (question 2), `tests/Feature/TenantRbacTest.php`.
POS: a new migration in `lib/data/postgres/migrations.dart` (next number after 54), `lib/domain/models/shift.dart` (`PosStaff.isOwner`), `lib/domain/services/authorization.dart`, `lib/domain/models/permissions.dart`, the 11 sites listed in section 1, `lib/data/postgres/local_bootstrap.dart`, `bin/pos_migrate.dart`, the setup controller.

## 7. Not done

No code, no migration and no test has been written for XORD-011. The existing cloud behaviour in section 1 was verified by reading source; the cloud suite was not run for it specifically.

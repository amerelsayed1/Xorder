# Feature specification: Restaurant staff accounts

Status: implemented (cloud API, dashboard SPA; staff reach the till through the bootstrap bundle)
Slug: `staff-management` · Module: `roles-and-staff` · Footprint: shared (bootstrap download; the POS also keeps local roles and grants)
Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; five independent passes (rounds 1-5), criterion not met: `docs/validation/2026-10-20-batch1-*-report.md`). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Summary
A restaurant owner, or a staff member with the staff capabilities, lists, creates, edits, suspends, deletes and resets the passwords of staff accounts of the same restaurant. Each staff account has a role that decides its capabilities. The owner account is listed (read-only) but cannot be shown, edited, reset or deleted through these endpoints. The number of staff accounts is capped by the restaurant's plan.

## Scope and exclusions
Implemented: the six staff routes, plan limit, credentials email, Vue list and form, the staff part of the POS bootstrap and the POS staff pane's cloud-till behavior. PINs are a separate feature (`pos-pin`); roles are `tenant-roles`; login is `auth-login`.
Not found (commands in `FEATURE_INVENTORY.md` "Absent", rows for `staff-management`): pagination on the staff list; soft deletes for users (hard delete); a cloud test of staff update success; any enforcement of the POS licence `max_users` in the cloud staff endpoint.

## Actors and permissions
| Actor | Capability | Enforced by | Evidence |
| --- | --- | --- | --- |
| Owner (`RESTAURANT_ADMIN`) | all tenant capabilities | `User::holdsTenantCapability` | `C:app/Models/User.php:115-119` |
| Staff with a role | the role's capabilities | same | `User.php:121-125`; a staff member with no role holds none |
| List / show | `staff.view` | `can:staff.view` | `C:routes/api.php:302-307` (the whole staff/roles block sits behind `auth:jwt` and `role:<tenant roles>`, `:271-272`) |
| Create | `staff.view` (enclosing group) then `subscription.writable` then `staff.create`; `StoreStaffRequest::authorize` checks `staff.create` again | route stack + request | `C:routes/api.php:302,309,316`, `C:app/Http/Requests/Dashboard/StoreStaffRequest.php:15-18` |
| Update / reset password | `staff.view` then `subscription.writable` then `staff.update` (+ `throttle:10,1` on reset, which the framework middleware priority list runs before `SubstituteBindings` and `can:`: `vendor/laravel/framework/src/Illuminate/Foundation/Http/Kernel.php:110-114`, from reading, not run) | route stack | `routes/api.php:302,309,317,320-322` |
| Delete | `staff.view` then `subscription.writable` then `staff.delete` | route stack | `routes/api.php:302,309,318` |
Gate registration: a loop over `TenantCapability::cases()` using `holdsTenantCapability`; `Gate::before` lets `SUPER_ADMIN` pass (`C:app/Providers/AppServiceProvider.php:120,135-139`). Platform roles cannot reach these routes (`role:` middleware lists tenant roles only; test `C:tests/Feature/UserCreationMatrixTest.php:411`).

## Current implemented behavior
1. `index`: users whose `restaurant_id` equals the caller's (no null guard: a null caller value is turned into `IS NULL` by the query builder, `vendor/laravel/framework/src/Illuminate/Database/Query/Builder.php:988-991`; whether a tenant-role account without a restaurant can exist: UNVERIFIED; the restaurant delete removes the tenant's users first, `C:app/Http/Controllers/Admin/RestaurantController.php:141-146`) with role `RESTAURANT_ADMIN` or `RESTAURANT_STAFF`, owner first then newest id first, not paginated, `tenantRole` eager-loaded (`C:app/Http/Controllers/Dashboard/StaffController.php:47-59`). The owner is listed and marked `is_owner` (test `C:tests/Feature/TenantRbacTest.php:508`).
2. `show`, `update`, `resetPassword`, `destroy` run `guardTarget` as the first statement of the action (for `update`, after the framework has resolved the route-bound `User` and `UpdateStaffRequest`, so an invalid payload gets 422 before `guardTarget` can answer 404/403; for `show`, `resetPassword`, `destroy` there is no FormRequest). `guardTarget` answers: 404 `staff_not_found` if the caller has no restaurant (on the mutating routes `subscription.writable` answers 403 first for a caller without a restaurant, `C:app/Http/Middleware/EnsureSubscriptionAllowsWrites.php:22-24`), the target is in another restaurant, or the target is not `RESTAURANT_STAFF` (this includes the owner); 403 `staff_self_forbidden` if the target is the caller (`StaffController.php:61-65,91-95,105-109,126-130,154-170`; each answer is `{message}` with the localized text only; an id that matches no user fails implicit model binding with the framework's own 404 before the action runs (no `Route::bind` in the app: `grep Route::bind` → no match)).
3. `store`: `StoreStaffRequest` authorizes and validates before the action body runs, then the action checks the plan limit — if `PlanLimitService::staffLimitReached` returns a limit, 422 `{message}` (not a validation `errors` shape) (`StaffController.php:75-79`); otherwise `TenantUserService::create`, 201 `{data, generated_password (null when a password was supplied), message}` (`:81-88`).
4. `TenantUserService::create` generates a password when none is given, hashes it, `forceCreate`s the user with role `RESTAURANT_STAFF`, the actor's `restaurant_id`, status (default ACTIVE), `email_verified_at` and `password_changed_at` now, then sends `StaffCredentials` if the user has an email and a restaurant (`TenantUserService.php:116-123`) (`C:app/Services/TenantUserService.php:33-63,116-123`). The mail contains the username and the plaintext temporary password; it is not queued (`C:app/Notifications/StaffCredentials.php:25-40`).
5. `update` sets name, username, email, `role_id` and status; a payload without `email` sets it to null (`$data['email'] ?? null`) (`TenantUserService.php:71-82`).
6. `resetPassword` generates a new 16-character password (no symbols), stamps `password_changed_at`, sends the mail if there is an email, records audit `staff.password_reset`, returns `{generated_password, message}` (`TenantUserService.php:89-101`, `StaffController.php:105-124`).
7. `destroy` deletes the user row (`User` does not use soft deletes: `grep -c SoftDeletes C:app/Models/User.php` → 0) and returns a message (`StaffController.php:126-135`).
8. Plan limit: `max_staff` of the plan named by `restaurants.subscription_plan`; a null or unknown plan, or a null max, means unlimited; the count is users with role `RESTAURANT_STAFF`, suspended ones included (the owner is not counted); reached when `count >= max` (`C:app/Services/PlanLimitService.php:53-75`). The only enforcement site found is `StaffController::store` (`grep max_staff` over `app` and `database`).
9. POS bootstrap: active tenant users (`RESTAURANT_ADMIN`, `RESTAURANT_STAFF`) are sent as `staff[]` rows `{id, name, username, role_id, capabilities (tenant capabilities minus purchase.manage, with legacy aliases), is_active: true, pin}` (`C:app/Services/PosBootstrapService.php:305-336`). The POS upserts them into `pos_staff` (PIN salt and hash `''` when absent), and sets rows missing from a non-empty bundle to inactive; rows are never deleted (`P:lib/data/cloud/bootstrap_seeder.dart:459-507`).
10. POS staff pane: when the deployment mode is not offline it shows that staff come from the platform and disables Add (`P:lib/features/admin/presentation/management_staff_pane.dart:134-148,171-183`); in the POS repository, create, set-active and PIN reset return `ManagedByPlatform` on a non-offline till, and `update` is refused only when it touches name, username, direct grants or branch (`P:lib/data/postgres/postgres_admin_repositories.dart:446-451,536-548,690-695,773-778`).

## User journeys and workflows
Owner opens Staff → creates a staff account choosing a role → when the server generated the password it is shown once (`generated_password`), and it is emailed only if the account has an email and a restaurant → the person signs in (`auth-login`). Reset password and suspend/delete follow the same page (`W:src/pages/dashboard/StaffView.vue:27,72,187`, `W:src/pages/dashboard/StaffForm.vue:54-62`).

## Business rules
| ID | Rule | Where implemented | Evidence |
| --- | --- | --- | --- |
| BR-1 | A staff account always belongs to the creator's restaurant and has role `RESTAURANT_STAFF`; `role` and `restaurant_id` in the payload are ignored. | service + non-fillable | `TenantUserService.php:33-63`; tests `TenantRbacTest.php:214`, `UserCreationMatrixTest.php:435` |
| BR-2 | The owner is listed read-only by `index` (marked `is_owner`) but `show`, `update`, `reset-password` and `destroy` answer 404 for it (for `update`, an invalid payload gets 422 first). | `guardTarget` | `StaffController.php:154-163`; tests `TenantRbacTest.php:527,550` |
| BR-3 | For a `RESTAURANT_STAFF` caller, `show`, `update`, `reset-password` and `destroy` answer 403 when the target is the caller's own account; an owner calling with their own id gets 404 because the role check comes first. | `guardTarget` | `StaffController.php:165-167`; test `TenantRbacTest.php:270` |
| BR-4 | The `role_id` in a create or update payload must name a role whose capabilities (expanded with implied views) the actor holds; `UpdateStaffRequest` applies the same check and `role_id` is required on update. | `rejectRoleAboveSelf` | `C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php:64-81`, `C:app/Http/Requests/Dashboard/UpdateStaffRequest.php:40-43`; tests `TenantRbacTest.php:327`, `UserCreationMatrixTest.php:296,312` |
| BR-5 | Usernames are unique per restaurant; emails are unique across all users; email is optional. | request rules + index | `StoreStaffRequest.php`; tests `UserCreationMatrixTest.php:348,376,391` |
| BR-6 | The plan's `max_staff` caps the number of `RESTAURANT_STAFF` accounts; the owner is not counted. | `PlanLimitService` | `PlanLimitService.php:53-66`; tests `C:tests/Feature/PlanStaffLimitTest.php:46,54,71,80,91,104` |
| BR-7 | A password reset stamps `password_changed_at`; the guard rejects tokens issued before it. | service + guard | `TenantUserService.php:89-101`, `C:app/Providers/AppServiceProvider.php:245-251`; test `TenantRbacTest.php:280` asserts only that `password_changed_at` increased (`:291`) |
| BR-8 | The mutating staff routes pass `subscription.writable` (`EnsureSubscriptionAllowsWrites`): 403 when the caller has no restaurant, or the restaurant status is ARCHIVED or SUSPENDED; and, while `ENFORCE_SUBSCRIPTION_WRITES` is on (default true), 403 `{message, code: subscription_inactive}` when the subscription status does not allow dashboard writes. `index` and `show` are outside this middleware. | route middleware | `C:routes/api.php:309-321`, `C:app/Http/Middleware/EnsureSubscriptionAllowsWrites.php:17-44`, `C:config/platform.php:171` |

## Validation and error handling
`StoreStaffRequest` (`C:app/Http/Requests/Dashboard/StoreStaffRequest.php`): `name` required string max 150; `username` required string min 3 max 150 regex `^[a-z0-9._-]+$` unique per restaurant; `email` nullable email max 255 globally unique; `role_id` required integer existing in `roles` for this restaurant; `status` nullable ACTIVE or SUSPENDED; `password` nullable string min 8 max 255; plus `rejectRoleAboveSelf`. `UpdateStaffRequest` is the same without `password`, with the uniqueness rules ignoring the target. `UpdateStaffRequest` is built at `C:app/Http/Requests/Dashboard/UpdateStaffRequest.php`. `resetPassword` and `destroy` take no FormRequest and no payload (`StaffController.php:105,126`). Errors: 422 (validation or plan limit), 404, 403 as above; every error body found in the controller is `{message}` with localized text (validation errors use the framework `errors` bag).

## Edge cases and failure handling
- Staff with no email can be created and sign in with a username (creation through the endpoint: `UserCreationMatrixTest.php:391`; sign-in of a factory-created email-less user: `TenantRbacTest.php:445`); no credentials mail is sent for them.
- A suspended owner who reaches the route through `actingAs` is refused with 403 by `EnsureRole` (`C:tests/Feature/UserCreationMatrixTest.php:423-431`, `C:app/Http/Middleware/EnsureRole.php:24-25`); with a real bearer token the guard returns no user for a suspended account, so the response is 401 (`C:app/Providers/AppServiceProvider.php:217-255`; see `auth-login`).
- Race, plan-limit and mail-failure conclusions: `BEHAVIORAL_ANALYSIS.md`.

## Cross-application dependencies
- The POS roster arrives through `GET /api/pos/bootstrap` only (no staff list call elsewhere); pairing uses a staff account's login JWT (`auth-login`), and the till sends the local staff id as the cloud user id (`acting_user_id` on order, refund, shift-open, shift-close and cash-movement uploads: `P:lib/data/cloud/outbox_drain.dart:163,249,687,754,810`; payments travel inside the order request and carry no such field; `:920` is a refund argument), and the cloud accepts an `acting_user_id` only for an ACTIVE user of the same restaurant, otherwise it answers 422 `VALIDATION_FAILED` with `acting_user_id: Unknown user.`; a null id is accepted; a known active user lacking the required verb gets 403 `POS_CAPABILITY_MISSING` (`C:app/Services/PosOrderService.php:470-484`; the same check in `PosShiftService.php:325-332`, `PosRefundService.php:316`, `PosCustomerService.php:94`); consequences for tills: `BEHAVIORAL_ANALYSIS.md` I; capabilities are renamed to POS keys (see `tenant-roles`); PINs travel in the same block (see `pos-pin`).
- Vue: `W:src/pages/dashboard/StaffView.vue`, `StaffForm.vue`; routes `W:src/router/index.js:170-172` (`staff.view`, `staff.create`, `staff.update`).
- How locally created POS staff ids relate to cloud ids: UNVERIFIED (cloud-bootstrapped staff share the cloud user id, `bootstrap_seeder.dart:465-486`).

## Security considerations
- Tenant boundary by hand (the `User` model is unscoped): `guardTarget` and the `restaurant_id` filter in `index` (see item 1 of the behavior list for the null case) (see `tenant-isolation`).
- BR-4 limits the role chosen in a create or update payload. `guardTarget` checks tenant, role `RESTAURANT_STAFF` and not-self only (`StaffController.php:154-170`); it does not compare the target's current capabilities with the actor's, and `resetPassword` and `destroy` take no payload, so BR-4 does not apply to them. Consequence for a holder of `staff.update`: `BEHAVIORAL_ANALYSIS.md` H. Platform roles cannot call the endpoints.
- Temporary passwords are emailed in clear text; `StaffCredentials` is not queued.
- Hard delete removes the row without a soft-delete trail; the only explicit audit call in the controller is `staff.password_reset` (`StaffController.php:114`). `User` uses the `Auditable` trait, which records `created`, `updated` and `deleted` model events (`C:app/Models/User.php:20`, `C:app/Models/Concerns/Auditable.php:22-27`); the password change is excluded from audit diffs by `User::$auditExclude` (`C:app/Models/User.php:24-26`).

## Known limitations
- Stale comments: `StaffController.php:17` says `can:staff.manage` and `:26-28` says the owner is invisible to the endpoint although `index` lists the owner (`:34-46`); `scoped()` (`:142-147`) has no caller in the file.
- No pagination; no `max_users` licence check in the cloud.
- Response of a plan-limit refusal is `{message}` only, not an `errors` bag.

## Existing automated tests
| Layer | File and test | Covers | Gaps |
| --- | --- | --- | --- |
| Cloud feature | `C:tests/Feature/TenantRbacTest.php:196,214,243,270,280,327,445,508,527,550,564` | create, forged payload, isolation, self-delete, reset stamps, role escalation, no-email login, owner listing and protection | PUT success and validation, `show` success, throttle on reset, `subscription.writable` 403, mail sent, `password` min 8, SUSPENDED on create, hard-delete effects |
| Cloud feature | `C:tests/Feature/UserCreationMatrixTest.php:258-452` (staff section) | creation matrix, escalation, uniqueness, generated password, platform roles refused | `holdsTenantCapability` is called with three arguments at `:201` and `:276` (extra arguments ignored by PHP) |
| Cloud feature | `C:tests/Feature/Pos/PosProvisioningTest.php:266-271` (bundle `staff[]` owner row: PBKDF2 `pin` block, `pos.operate` in `capabilities`), `C:tests/Feature/Pos/PosPurchaseCapabilityWithheldTest.php:20-27` (`purchase.manage` withheld from `staff[].capabilities`) | bundle staff block | other rows, `is_active`, non-owner staff |
| Cloud feature | `C:tests/Feature/PlanStaffLimitTest.php:46-104`, `C:tests/Feature/CapabilityVerbsTest.php:166-179` | limit, independent verbs | limit on update; `max_users` |
| POS (integration-tagged, needs `POS_PG_HOST`) | `P:test/data/postgres_admin_test.dart:417-499` | cloud-till refusals (add, rename, PIN reset, disable), role assignment allowed | skipped without a database |
| POS | `P:test/data/cloud_bootstrap_test.dart:145-150` | staff PIN block parsed, missing PIN tolerated | no test of `_seedStaff` found |

## Acceptance criteria
- AC-1: A staff-capable user creates a staff account in their own restaurant with a role they could themselves hold; the generated password is returned once.
- AC-2: Staff accounts of other restaurants and the owner account are not reachable through `show`, `update`, `reset-password` and `destroy` (404; for `update`, an invalid payload gets 422 first); the owner still appears in the `index` list.
- AC-3: A staff user cannot edit, reset or delete their own account here (403); an owner's own id is 404.
- AC-4: The plan's staff cap is enforced on create and does not count the owner.
- AC-5: Platform roles cannot manage staff (403), and a suspended account is refused (401 at the guard, 403 when a user is injected without it).
- AC-6: Staff arrive at the till through the bootstrap with their capabilities and PIN verifier.

## Confirmed source references
`C:routes/api.php:300-322`; `C:app/Http/Controllers/Dashboard/StaffController.php`; `C:app/Http/Requests/Dashboard/{StoreStaffRequest,UpdateStaffRequest}.php`; `C:app/Http/Requests/Dashboard/Concerns/GrantsTenantCapabilities.php`; `C:app/Services/{TenantUserService,PlanLimitService,PosBootstrapService}.php`; `C:app/Notifications/StaffCredentials.php`; `W:src/pages/dashboard/{StaffView,StaffForm}.vue`; `P:lib/data/cloud/bootstrap_seeder.dart:459-507`; `P:lib/features/admin/presentation/management_staff_pane.dart`.

## Unknowns and assumptions
- `TenantRoleService::ungrantable` expands the requested capabilities and keeps those the actor does not hold (`C:app/Services/TenantRoleService.php:128-140`).
- `StaffForm.vue:65` stores only `err.response?.data?.errors` (or `{}`) on failure and shows no other message, so the plan-limit 422 (`{message}` only, `StaffController.php:75-79`) displays nothing in that form (from reading the handler; template rendering of `errors` not traced).
- UNVERIFIED: the licence `max_users` setting and enforcement; the 429 body; the body of a `can:` denial; the framework order of `throttle` relative to `can:` on the reset route.
- UNVERIFIED: how locally created POS staff reconcile with cloud staff ids.

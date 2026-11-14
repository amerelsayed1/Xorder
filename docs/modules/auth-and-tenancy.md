# Module: auth-and-tenancy

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8`
Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`.
Status: core `drafted` for 4 of 4 features · Footprint: mostly cloud; POS uses login only to pair a till

## Purpose and scope
Who may enter the platform and how data is kept apart per restaurant: login and the stateless bearer token, password change and email reset, self-service signup (flag-gated), and the tenant scope applied to data.

## Features
| Slug | Title | Footprint | Status | Docs |
| --- | --- | --- | --- | --- |
| `auth-login` | Login, session token and password change | shared (POS client call verified) | drafted | `docs/features/auth-login/` |
| `auth-password-reset` | Password reset by email | cloud-only | drafted | `docs/features/auth-password-reset/` |
| `auth-signup` | Self-service restaurant signup | cloud-only | drafted | `docs/features/auth-signup/` |
| `tenant-isolation` | Tenant isolation (restaurant scope) | cloud-only | drafted | `docs/features/tenant-isolation/` |

## Actors and permissions
Anonymous callers (login, forgot/reset, signup); any signed-in user (logout, me, change password); platform vs tenant roles (`EnsureRole`); capabilities are in `tenant-roles`.

## Architecture of the module
Cloud: `Auth\AuthController`, `Auth\PasswordResetController`, `Public\SignupController`, `Support\Jwt` and the `jwt` guard in `AppServiceProvider`, `TenantContext`/`RestaurantScope`/`BelongsToRestaurant`. Web: `LoginView`, router guard, shared API client. POS: `login` in `cloud_api.dart` for pairing.

## Data
`users`, `password_reset_tokens`, `restaurants`, `roles`, `restaurant_features`, `pos_licences` (signup); `restaurant_id` on all tenant tables.

## Module-level workflows
Sign in → token → guarded requests; change password → new token; forgot → emailed link (no client page found) → reset; signup (flag) → owner email → sign in.

## Cross-application dependencies
POS posts `POST /api/auth/login` once while pairing (`P:lib/data/cloud/cloud_provisioning_repository.dart:82`); POS requests are tenant-scoped by the device middleware, not by login.

## Dependencies on other modules
`roles-and-staff` (roles, capabilities), `pos-provisioning-licensing` (licence created at signup, device tokens), `platform-admin` (plans/features).

## Tests
Cloud: `AuthTest`, `PerTenantAuthTest`, `JwtRoundTripTest`, `ChangePasswordTest`, `SecurityHardeningTest`, `SignupTest`, `TenantIsolationTest`. Gaps listed per feature (expired token, `rid`, logout, throttles, scope unit tests).

## Risks, gaps and unknowns
See each feature's `BEHAVIORAL_ANALYSIS.md` (unvalidated) and Unknowns: no client for forgot/reset, logout does not revoke, unscoped models rely on controller guards.

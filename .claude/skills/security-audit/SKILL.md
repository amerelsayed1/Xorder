---
name: security-audit
description: Read-only security review of Xorder auth, authorization, tenant isolation, money/order integrity and data handling. Use whenever the user asks for a security review or audit, "is this endpoint safe", "check permissions", "can one restaurant see another's data", a tenant leak, JWT or login hardening, idempotency or totals tampering, or secrets/PII exposure, even if they only name one route or screen.
argument-hint: "<area or feature slug>"
---

# Security Audit

Knowledge: before significant changes follow `.claude/rules/knowledge.md` (`/project-documentation context <feature> <phase>`); verify critical behavior in current source, and report missing or stale docs.

Read-only; do not access real user data, `.env*` files, key files or the backups folder. Use `security-reviewer` for an independent pass.

## Procedure
1. **Authn (cloud)**: stateless JWT bearer via `app/Support/Jwt.php` + `config/jwt.php` (not Sanctum); check token expiry, secret handling (`JWT_SECRET`), login/password-change and rate limiting.
2. **Authz & tenancy (cloud)**: every dashboard route stacks `role:` + `feature:` + `can:` (+ `subscription.writable`); per-object checks via Gate definitions in `AppServiceProvider` and service-level capability checks (there is no `Policies/` directory); `RestaurantScope`/`BelongsToRestaurant` on tenant models; `restaurant_id` never from input; cross-tenant access returns 404. `User` has no scope — verify manual scoping in staff queries. Platform `Capability` vs restaurant `TenantCapability` must not leak across.
3. **Money/order integrity**: server computes totals (`PosPricingEngine`); POS orders idempotent with payload-hash mismatch rejected (`PosOrderService`); transitions validated server-side; refunds and shifts authorized.
4. **POS**: Ed25519 offline licence verification, PBKDF2 cashier PIN, device token storage (`device_token_vault.dart`), local PostgreSQL credentials, no secrets in logs/receipts.
5. **Input & output**: Form Request validation, mass-assignment (`$fillable`), file/image upload handling, `*PublicResource` for public output, activity-log redaction (`AuditSecretsTest`).
6. **Secrets/logging**: nothing sensitive in repo, docs, logs or test fixtures.
7. **Operational abuse**: read `docs/domain/FOOD_SERVICE_DOMAIN.md` section 5 and test the controls against it: voids after send, discounts, refunds to cash, no-sale drawer opens, price overrides, hidden shortages; each needs a capability, a reason, an approver where required, and an audit record.
8. Cross-check existing audits (`apps/xorder-cloud/docs/audits/`, `apps/xorder-cloud/docs/XORDER_PRE_LAUNCH_SECURITY_AUDIT.md`) and existing tests before reporting a gap as new.

Report vulnerabilities with `path:line` evidence, severity and remediation; mark unverified items.

## Required output
Report scope, verified file paths, assumptions/unknowns, changed files (if any), exact tests run with outcomes, risks and next action. Follow workspace `CLAUDE.md` approval rules.

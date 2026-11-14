# API contract: Self-service restaurant signup

Verified against: 2026-10-20 · cloud `main 06bc8e3` · POS `main d592db8` (uncommitted files in both repos are documentation, agent/script files and two POS files outside this feature; none is cited as evidence unless stated). Core state: `drafted` (author self-check, mechanical citation check; no independent validation pass). Path prefixes: `C:` = `apps/xorder-cloud/apps/api/`, `P:` = `apps/xorder-pos/`, `W:` = `apps/xorder-cloud/apps/web/`, `K:` = `apps/xorder-cloud/packages/`, `A:` = `apps/xorder-cloud/apps/`.

## Producers and consumers
`POST /api/public/signup` — producer `C:app/Http/Controllers/Public/SignupController.php:26-70`; consumers: none found.

## Verified endpoints
| Method | Path | Middleware | Controller@method | Route |
| --- | --- | --- | --- | --- |
| POST | `/api/public/signup` | `throttle:5,10` | `Public\SignupController@store` | `C:routes/api.php:841` |

## Authentication and authorization
None; gated by the configuration flag (404 when off).

## Request and response examples (redacted)
Body: `restaurant_name`, `restaurant_name_ar?`, `name`, `email`, `whatsapp?`, honeypot `website?` (rules in `FEATURE.md`).
201: `{"data": {"public_url": "...", "login_url": "...", "trial_days": 14}, "message": "..."}`; honeypot 201: `{"message": "..."}` only.

## Error formats
404 (flag off); 422 Laravel error bag (duplicate email under `email`); 429 throttle (shape UNVERIFIED).

## Idempotency, retries and concurrency
Not idempotent; duplicate detection is the email uniqueness rule and slug uniqueness (`RestaurantProvisioningService.php:71-73`, comment names the DB unique index on `restaurants.slug` as the ultimate guard: `C:database/migrations/2026_06_27_002001_create_restaurants_table.php:15`).

## POS and other client usage
None found.

## Backward compatibility
No contract-ledger item. Response keys are additive-safe.

## Contract tests
`C:tests/Feature/SignupTest.php:28-78` (see `FEATURE.md`).

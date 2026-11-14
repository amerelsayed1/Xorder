# API contract: <feature title>

Verified against: <date> · cloud `<HEAD>` · POS `<HEAD>`
Headings keep the order of `docs/templates/API.md`; (+) sections are added by `/project-documentation`. Endpoints come from route files only; do not list a route you did not find.

## Producers and consumers
| Endpoint group | Producer (controller) | Consumers (Vue file, POS file, external) |
| --- | --- | --- |

## Verified endpoints (method/path)
| Method | Full path | Middleware stack | Controller@method | Route file:line |
| --- | --- | --- | --- | --- |
(The API has no `/v1` prefix; resolve group prefixes before writing the full path.)

## Authentication and authorization
| Endpoint | Guard | Role / capability / feature / subscription gate | Tenant boundary | Evidence |
| --- | --- | --- | --- | --- |

## Request and response examples (redacted)
### `<METHOD> <path>`
Validation rules (from the FormRequest, `path:line`):
```
field: rule
```
Response shape (from the Resource or a test; redacted):
```json
{}
```

## Error formats
(HTTP codes, error body shape, message keys; cross-tenant behavior such as 404 vs 403; validation error shape.)

## Idempotency, retries and concurrency (+)
(Idempotency keys, duplicate-submission handling, optimistic locking, transaction boundaries.)

## POS and other client usage (+)
| Client call site | Endpoint | Request/response model | Contract ID / status |
| --- | --- | --- | --- |

## Backward compatibility
(Additive vs breaking changes, versioning by contract ID, minimum client versions, copies of coordination docs that disagree.)

## Contract tests
| Test file and name | Endpoint | Covers | Gaps |
| --- | --- | --- | --- |

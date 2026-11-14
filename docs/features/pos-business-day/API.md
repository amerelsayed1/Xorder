# API contract: POS business day

## Producers and consumers
None. This feature adds no endpoint and changes no request or response. `P:lib/data/cloud` carries no business day on any sync payload.

## Verified endpoints (method/path)
None added. (Existing and untouched: `GET /api/pos/branch/sales/summary?business_day=YYYY-MM-DD`, `P:docs/coordination/POS_TO_BACKEND.md:1554`, a cloud-side query.)

## Authentication and authorization
Not applicable.

## Request and response examples (redacted)
Not applicable.

## Error formats
Not applicable.

## Backward compatibility
No change to any contract. **Open contract item, not part of this feature:** the platform wants each synced order's business day (CB-10 "business-day field on orders", `P:docs/coordination/BACKOFFICE_TO_CLOUD.md:347-352`; `P:docs/coordination/POS_TO_BACKEND.md:1644-1650`, status PROPOSED, additive). Now that the till files its rows under a day it could send it; that needs the cloud half first and approval.

## Contract tests
None.

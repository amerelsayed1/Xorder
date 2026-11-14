# API — finance-account-kind-per-method
2026-10-26. Cloud routes in `apps/xorder-cloud/apps/api/routes/api.php`; no `/v1` prefix, additive only.

| Endpoint | Change | Compatibility |
|---|---|---|
| `PUT /api/dashboard/tender-account-defaults` (`finance.accounts`) | **A request that used to succeed can now be refused:** `422` with `errors.financial_account_id[0]` = `xorder.validation.account_kind_mismatch` (en/ar) when the account's kind does not fit the method's kind. Request and response shapes unchanged. | An old dashboard sending a mismatch gets the 422 and its message. |
| `POST` / `PUT /api/dashboard/tender-types` (`StoreTenderTypeRequest`, `UpdateTenderTypeRequest`) | `kind` now accepts `wallet` besides `cash`, `card`, `external`, `other`. | Additive: every old value is still accepted. |
| `GET /api/pos/bootstrap` (`money.tender_types[].kind`) | May now be `wallet`. Shape unchanged. | An older POS build reads an unknown kind as `null` (`PlatformTenderKind.fromWire`), and the seeder files it as a takeable tender that is not cash — it keeps selling, it just cannot pair a wallet account until updated. |
| Branch-sales reads (`kind` per payment) | May be `wallet`. | Older POS: unknown → `other`. Newer POS: `TenderKind.wallet`. |
| `GET /api/dashboard/tender-account-defaults`, `financial-accounts` | Unchanged. A default saved before the rule is returned as it is. | — |

## The pairing (both sides)
| Method kind | Pays into account kind |
|---|---|
| `cash` | `cash` |
| `card`, `external` | `bank` |
| `wallet` | `wallet` |
| `other` | any (null) |
POS `AccountRules.kindsFor(TenderKind)` holds the till's copy (`wallet` there is the same word; `external` is read as `card`).

## Rollout order
1. **Cloud first**: it starts accepting `wallet` and enforcing the pairing.
2. **POS after**: new builds read `wallet`. Until then a till that receives a `wallet` method treats it as an ordinary non-cash method.
Nothing in the POS depends on the cloud being updated: an offline till has its own repository check.

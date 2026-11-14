# Branch order number — API
Status: 2026-10-28 · **No cloud/API change.** The POS sync payload (`_enqueueForSync`) is deliberately **not** changed: offline mode sends nothing to the cloud, and cloud-mode branches with several tills are a separate later item (owner decision 2026-10-28). No new endpoint, no `POS-BE` item, nothing for `xorder-cloud`.

Internal POS contract (Dart): `SubmitOrderResult.dayOrderNumber` (`int?`) and `OrderRecord.dayOrderNumber` (`int?`), both nullable and additive; `ReceiptData.dayOrderNumber`.

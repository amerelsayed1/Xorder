# API — pos-signin-first-home

Not applicable, verified 2026-10-27: this feature adds, changes or calls **no** cloud route, request or response (`grep` of the touched files finds no `lib/data/cloud` use). Sign-in verifies against the cached staff hash on the till (`SessionRepository.signInAs`), as the lock screen does; the optional sync nudge (`cloudSyncProvider?.nudge()`) is the existing mechanism. No contract item (`POS-BE-xxx`, `CB-xx`) is involved; cloud and POS deploy independently with nothing to order.

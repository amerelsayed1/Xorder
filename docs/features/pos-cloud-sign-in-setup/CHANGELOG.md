# Changelog — pos-cloud-sign-in-setup

## 2026-11-08 — built (uncommitted), xorder-pos `development` on `9f1b7d2`
- Cloud app setup starts with the owner's sign-in (`____.xorder.io`, username, password); no licence step, no licence-server field, no pairing-code screen (D2, D5).
- Only the owner (`RESTAURANT_ADMIN`) may continue; any other account gets `NOT_OWNER` before any branch or terminal call (D3). Server rule unchanged.
- The licence comes only from the bootstrap bundle and is checked at the connecting step; missing, offline-mode, both-modes, other-business or non-trading licences stop setup with a reason and "Try again" (BR-5, D4).
- Removed: `SetupMethod`, the pairing-code pane and controller path, 16 strings. Added strings (en + ar): `businessAddress`, `businessAddressHelp`, `ownerSignInHelp`, `stepOwnerSignInBlurb`, `cloudLicenceMissing`, `refusalNotOwner`.
- Offline app and child-tablet path unchanged (D6).
- End-to-end driver rewritten for the owner walk; the spent-pairing-code e2e test and the suite's own licence signing removed. Not run.

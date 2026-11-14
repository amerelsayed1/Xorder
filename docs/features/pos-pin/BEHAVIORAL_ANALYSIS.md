# Behavioral analysis: Cashier PIN for the POS

Status: **UNVALIDATED (from reading).** Excluded from `/project-documentation validate`; never counts toward `validated`. Each entry is a lead: re-trace the code before relying on it. Nothing here was executed; no test was run. Evidence came from read-only analyst sweeps whose single-location facts were spot-checked by the author; the traced conclusions below were not independently checked.
Written against: cloud `main 06bc8e3` · POS `main d592db8`. Path prefixes as in `FEATURE.md`.

## A. Config-version bump and tills
- Claim: only the PIN controller bumps the version, so PIN changes are signalled; whether tills poll the version or re-download on a schedule was not read
- Trace: `C:app/Http/Controllers/Dashboard/PosPinController.php:44,65`
- Confidence: low. Would be confirmed by: read the POS sync code and bootstrap ETag handling

## B. Cleared PIN locks the cashier out only at the next sync
- Claim: the controller comment says so
- Trace: `PosPinController.php:56`
- Confidence: medium. Would be confirmed by: a POS test

## C. No PIN on the till
- Claim: salt and hash are stored as `''`; `verify` should fail; the Dart crypto behavior with an empty nonce was not confirmed
- Trace: `P:lib/data/cloud/bootstrap_seeder.dart:480-481`, `P:lib/core/security/pin_hash.dart:61-74`
- Confidence: medium. Would be confirmed by: a POS test

## D. PHP/Dart compatibility
- Claim: both implementations agree by reading parameters, but no test crosses them
- Trace: `C:app/Support/PosPin.php:19-36`, `P:lib/core/security/pin_hash.dart:38-55`
- Confidence: medium-high. Would be confirmed by: a shared fixture test

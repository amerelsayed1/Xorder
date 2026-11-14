# API: Content languages (XORD-005)

No endpoint was added or changed by the POS stage. The platform flag reaches the till as `bilingual` (+ `default_language`) in the POS bootstrap bundle (`C:app/Services/PosBootstrapService.php:83`), parsed by `P:lib/data/cloud/bootstrap_bundle.dart` into `ContentLanguages.fromPlatform`. An older platform that sends neither leaves the till's setting alone.
Cloud request validation (13 name checks, `PreservesDisabledLanguages`) is described in the tracker; **UNVERIFIED** in this session beyond `ContentLanguagesTest`.

# API contract: two POS apps on shared modules

Verified against: 2026-11-08 · POS `development` `7fa0d06` · cloud `feat/licence-one-mode` `30b1529` (not merged into `development` or `main`, not pushed). Paths are relative to `apps/xorder-pos/` unless they start with `apps/xorder-cloud/`.

## Summary
**No endpoint is added, removed or reshaped.** No route, request field, response field or error code changes for the POS ↔ cloud contract (FEATURE.md section 10, TECHNICAL.md section 5). The POS stages 1–3 only move code between packages; the HTTP client `packages/shared_module/lib/data/cloud/cloud_api.dart` is shared by both apps, and the callers of the sales endpoints (outbox drain, cloud sync, provisioning, bootstrap, branch sales, logo sync) now live only in `apps/xorder_pos_cloud/lib/data/cloud/`.

The one contract-relevant change is on the cloud side (stage 6, D1/BR-2): the Super Admin can no longer issue a licence covering both modes.

## Producers and consumers
| Surface | Producer | Consumer after the split |
| --- | --- | --- |
| POS sales, shifts, refunds, bootstrap, provisioning endpoints (`/api/pos/...`) | cloud, unchanged | cloud app only (`apps/xorder_pos_cloud/lib/data/cloud/`) through the shared `cloud_api.dart`. The offline app has no code path to them (`package_boundaries_test.dart`; AC-5 flow test not yet written, stage 4) |
| Licence renewal endpoint used by the till | cloud, unchanged | both apps, through the shared `cloud_api.dart`; importers on `7fa0d06`: `packages/shared_module/lib/features/licensing/data/online_licence_service.dart`, `.../licensing/data/licence_check_gate.dart`, `lib/app/providers.dart` (`git grep`) |
| Super Admin licence issuing and renewal | cloud | Vue Super Admin forms `RestaurantForm.vue`, `pos/LicenceForm.vue`, `pos/LicenceDetails.vue` (radio buttons on `30b1529`) |

## Stage 6: one mode per licence (cloud, branch `feat/licence-one-mode`, `30b1529`)
Routes (all under the `admin` prefix, `auth:jwt` + Super Admin roles; read from `apps/xorder-cloud/apps/api/routes/api.php` on `30b1529`):

| Method | Path | Request class | Rule on `modes` |
| --- | --- | --- | --- |
| POST | `/api/admin/pos/licences` (`can:licences.manage`) | `Admin\StoreLicenceRequest` | `required`, `array`, `min:1`, plus `oneModeRule()` |
| POST | `/api/admin/pos/licences/{licence}/renew` (`can:licences.manage`) | `Admin\RenewLicenceRequest` | `nullable`, `array`, `min:1`, plus `oneModeRule()`; and `withValidator`: a renewal that omits `modes` is refused when the licence being renewed covers two modes |
| POST | `/api/admin/restaurants` (`can:restaurants.manage`) | `Admin\StoreRestaurantRequest` | `licence.modes`: `nullable`, `array`, `min:1`, plus `oneModeRule()` |
| POST | `/api/admin/pos/licences/offline` | `Admin\StoreOfflineLicenceRequest` | unchanged: `modes` is forced to `['offline']` server-side |

- **The rule** (`StoreLicenceRequest::oneModeRule()`): counts distinct modes with the legacy wire values `branch_server` and `standalone` folded into `offline` (`modeOf`, `modeCount`). So `['cloud']`, `['offline']` and `['offline','standalone']` pass; `['cloud','offline']` fails.
- **Not** `array|size:1` as TECHNICAL.md stage 6 "Change" planned; the as-built closure is what ships (see "Contradictions" in the stage-7 report and TECHNICAL.md "As built").
- **Errors:** standard Laravel 422 validation envelope on `modes` (or `licence.modes`), messages `xorder.validation.licence_one_mode` ("A licence covers one mode: cloud or offline, not both.") and `xorder.validation.licence_one_mode_renewal`, in en and ar (`apps/api/lang/{en,ar}/xorder.php`).
- **Response shapes:** unchanged. `modes` is still an array, now always of one mode.
- **Compatibility:** narrows an input only. Old single-app tills already accept one-mode licences (TECHNICAL.md stage 6 "Rollout"). Existing licences signed for both modes are not changed by the cloud; both new apps refuse them (D9) and they must be reissued. How many exist in production is UNVERIFIED (production not read).
- **Rollout:** independent of the POS stages; reaches `main` only after `/release-check` and the owner's push. No migration.

## Till-side licence handling (no wire change)
Stage 2 changed how the till judges a licence it already receives, not the payload: `LicenseVerifier.singleModeOnly`, `LicenseState.modeAmbiguous` (both modes, D9), `LicenceModeNotCovered(fixedApp: true)` naming the other app (TECHNICAL.md stage 2). The licence claim format is unchanged.

## Unknowns
- UNVERIFIED: which endpoints `online_licence_service.dart` calls was not re-read; only that it imports `cloud_api.dart` was checked.
- UNVERIFIED: the Super Admin forms were not opened in a browser (TECHNICAL.md stage 6 "Not done").

# Test plan — pos-cloud-sign-in-setup

Verified against xorder-pos `development` `9f1b7d2` + working tree (2026-11-08).

| AC | Test (file › name) | Kind |
|---|---|---|
| AC-1 | `shared_module/test/features/setup_wizard_test.dart` › wizard UI › "the cloud app opens on the owner sign-in, and nothing else" | widget |
| AC-2 | `setup_wizard_test.dart` › provisioning › "connecting pulls the tenant configuration for the next steps" | unit |
| AC-3 | `setup_wizard_test.dart` › provisioning › "the owner signs in and adopts the till the dashboard made" | unit |
| AC-4 | `cloud_setup_collapsed_test.dart` › walk via the fake (adopt); `xorder_pos_cloud/test/data/cloud_provisioning_owner_test.dart` › "a full till count is said as the platform said it" (register refusal) | widget / unit |
| AC-5 | `cloud_setup_collapsed_test.dart` › "the screens a cloud main device is shown"; › "the licence the platform sent" › "fixed on the dashboard, Try again finishes the step" | widget |
| AC-6 | `cloud_setup_collapsed_test.dart` › "the licence the platform sent" › "none at all…", "one for the offline app is refused, by name" | widget |
| AC-7 | `cloud_provisioning_owner_test.dart` (staff refused with zero further calls; no role is not owner; adopt and register refuse a non-owner); `setup_wizard_test.dart` › "an account that is not the owner's is refused and pulls nothing" | unit |
| AC-8 | `cloud_provisioning_owner_test.dart` › "a wrong password is still a wrong password"; `setup_wizard_test.dart` › "a rejected connect says so and pulls nothing" | unit |
| AC-9 | `setup_persistence_test.dart` › "a claim made on an earlier run" › "is written the moment the till is claimed" (no `password` in the record) | unit |
| AC-10 | `setup_wizard_test.dart` › "the cloud app opens on the owner sign-in…" (no `LICENCE SERVER`, `LICENCE KEY`, `SETUP CODE`) | widget |
| AC-11 | `setup_wizard_test.dart` › "the offline app opens on the licence, as it always has", "the offline wizard opens on the licence and stops there unlicensed"; the whole `xorder_pos_offline` suite | widget / suite |
| AC-12 | `test/core/localisation_test.dart` (catalogue checks over every key, `businessAddress` listed) | unit |

**Gaps (need a person or an environment):**
- AC-12: the Arabic sign-in screen looked at by a person (RTL layout, the `.xorder.io` suffix staying left-to-right).
- End to end: `apps/xorder_pos_cloud/integration_test/sale_to_settle_test.dart` against a local API with an owner account and a cloud-only licence (see its README).
- The real platform's `role` field: verified by reading `UserResource.php:20` on xorder-cloud `main`, not by a call.

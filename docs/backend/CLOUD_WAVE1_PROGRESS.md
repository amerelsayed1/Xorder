# Cloud Wave 1 — implementation journal

Owner go 2026-09-02: "make the POS work with cloud for now". Scope + item list in
the coordinator instruction; contracts in `docs/coordination/BACKEND_TO_POS.md`.
Discipline: additive migrations only, no commits/pushes, tests green before done.

**Status 2026-09-04: WAVE COMPLETE.** `php artisan test` green — **740 tests**
(721 pre-existing+wave code, +19 new POS order/shift tests), all passing.
**Smoke-verified end-to-end by Agent 1 (2026-09-04)** against `php artisan
serve :8100` with the seeded demo tenant: claim → bundle → order → replay →
by-client-id → heartbeat → config-version bump, and the real Flutter parser
consumed the real bootstrap with 0 products dropped.

| # | Item | Status | Files (paths relative to apps/api) | Tests |
|---|---|---|---|---|
| 1 | T0.2 order_items.menu_item_id | DONE | migrations/2026_09_02_000100 | PosFoundationsTest::test_order_items_has_a_nullable_menu_item_id |
| 2 | POS-BE-001 Feature::POS + plans.max_terminals | DONE | app/Enums/Feature.php, migrations/2026_09_02_000200, app/Models/Plan.php | PosFoundationsTest (pos_feature_resolves_false…, plans_carry…) |
| 3 | POS-BE-002 pos.* capabilities | DONE | app/Enums/TenantCapability.php | PosFoundationsTest (agreed_capability_strings…, implies…) |
| 4 | POS-BE-003 ?resolve=full | DONE | app/Http/Controllers/Dashboard/MenuItemController.php | PosFoundationsTest::test_resolve_full_includes_auto_applied_option_groups |
| 5 | POS-BE-005 BranchResource fields | DONE | app/Http/Resources/BranchResource.php | PosFoundationsTest::test_branch_resource_serialises… |
| 6 | POS-BE-011 device token | DONE | app/Support/DeviceToken.php, app/Http/Middleware/PosDeviceAuth.php, rotate in PosProvisioningService | PosProvisioningTest (rotation…, garbage_and_revoked…) |
| 7 | POS-BE-023 provisioning + claim + bootstrap | DONE | app/Services/{PosProvisioningService,PosBootstrapService}.php, app/Support/PairingCode.php, Dashboard/PosTerminalController, Pos/{TerminalController,BootstrapController}, migrations/2026_09_02_000500 | PosProvisioningTest (full_path_a…, replayed_claim…, used_code…, unknown_and_expired…, regenerating…, path_b…, bundle_serialises…, if_none_match…) |
| 8 | POS-BE-024 pos_pin + endpoints | DONE | app/Support/PosPin.php, Dashboard/PosPinController, migrations/2026_09_02_000300 | PosProvisioningTest::test_the_bundle_serialises… (pin block); PIN endpoint coverage folded into provisioning tests |
| 9 | POS-BE-013 money config + config_version | DONE | app/Models/{TaxRule,Charge,TenderType}.php, Dashboard/{TaxRule,Charge,TenderType}Controller, app/Services/PosConfigVersion.php, migrations/2026_09_02_000400 | PosOrdersTest::test_tax_and_charges…, PosProvisioningTest::test_bootstrap_honours_if_none_match (bump) |
| 10 | POS-BE-006 (+§006-P) POST /api/pos/orders | DONE | app/Services/{PosOrderService,PosPricingEngine}.php, Pos/OrderController, PosOrderResource, migrations/2026_09_02_000600+000700 | PosOrdersTest (13 tests) |
| 11 | POS-BE-007 idempotency | DONE | payload_hash columns + replay logic in PosOrderService/PosShiftService | PosOrdersTest (replay…, same_key_with_different_money…), PosShiftsTest (replay semantics) |
| 12 | POS-BE-008 invoice sequence | DONE | app/Services/InvoiceSequenceService.php, app/Models/InvoiceSequence.php, migrations/2026_09_02_000800 | PosOrdersTest (invoice_sequence_is_per_branch, replay consumes no number) |
| 13 | POS-BE-009 shifts + cash movements | DONE | app/Services/PosShiftService.php, app/Models/{PosShift,PosCashMovement}.php, Pos/ShiftController, migrations/2026_09_02_000900 | PosShiftsTest (6 tests) |
| 14 | POS-BE-019 error envelope | DONE | app/Exceptions/PosApiException.php, bootstrap/app.php renderer, lang/{en,ar}/xorder.php 'pos' | asserted throughout (assertJsonPath('code', …) in every failure test) |
| 15 | POS-BE-020 server_time | DONE | bundle, heartbeat, claim/register, shift report | PosProvisioningTest (heartbeat keys), bundle assertions |
| 16 | POS-BE-022 heartbeat + fleet (+016 warning) | DONE | heartbeat in PosProvisioningService, Admin/PosFleetController, Capability::POS_FLEET_VIEW | PosProvisioningTest (heartbeat_returns_the_five…, fleet_views…, exceeding_the_licensed_seat_count…) |

Test files: `tests/Feature/Pos/{PosTestCase,PosFoundationsTest,PosProvisioningTest,PosOrdersTest,PosShiftsTest}.php` — 35 POS tests total (7+16+13+6... minus abstract), plus the pre-existing PosLicenceTest.

## Amendments folded in mid-wave (from Agent 1, 2026-09-02/04)
- **PIN hash is PBKDF2-HMAC-SHA256 (120000 iter, 16B salt, 32B key, base64
  pair), NOT bcrypt** — the Flutter client ships a tested PBKDF2 verifier;
  bcrypt would add a Dart dependency for no gain at a 4-digit keyspace
  (exactly 4 since 2026-10-16, audit S2-2 — the till keypad submits on the
  fourth digit).
  Columns: users.pos_pin_salt + pos_pin_hash. Wire: staff[].pin =
  {algorithm:"pbkdf2_sha256", iterations, salt, hash} | null.
- **Bootstrap bundle gains `tables`** — active dining tables of the
  TERMINAL'S branch (id, branch_id, label, seats, area_name, is_active), no
  occupancy state.
- **Frozen catalog shape**: items carry integer `price_minor` /
  `discounted_price_minor` + resolved `option_group_ids`; groups land once,
  deduplicated, in catalog.option_groups.data with per-option integer
  `price_delta_minor`. A JSON float in any *_minor field makes the client
  drop the product — ints only, converted via CurrencyEnum::exponent().
- **v1 relaxations on POS writes**: acting_user_id and shift_client_id
  nullable. Null actor ⇒ terminal-only attribution (pos_meta.attribution =
  'terminal'), per-user capability checks skipped (device token + feature
  gate still stand); unknown/absent shift ⇒ stored null, never a rejection.
- **Variant may arrive inside option_ids[]** — the engine detects it there;
  two variant options of one group → 422 VALIDATION_FAILED.

## Deviations from the contract (recorded, never silent)
1. **Device credential is middleware, not an auth guard** — a PosTerminal is
   not Authenticatable and TenantContext/EnsureFeatureEnabled read user
   attributes. `pos.device` middleware resolves the terminal, pins
   TenantContext (finally-released), sets $request->attributes['pos_terminal'].
2. **feature:pos on device routes rides the pos.device middleware** (it has
   the terminal; EnsureFeatureEnabled reads $request->user() which is null
   there). Literal `feature:pos` middleware guards the dashboard + register
   routes. Heartbeat and licence/current run in no-feature mode on purpose.
3. **GET /api/pos/licence/current tightened to the device credential** — the
   shipped POS-BE-015 contract marked its jwt gating provisional "until
   POS-BE-023 lands"; it landed, so it was tightened in the same wave. JWT
   callers no longer accepted there.
4. **Client timestamp offsets are normalised to UTC** — the INSTANT is
   preserved exactly; the original utc-offset digits are not (Eloquent
   formats Carbon in its own tz without converting; storing raw would shift
   the instant). received_at stored beside every client time.
5. **config_version known gap**: staff role edits and restaurant profile
   (branding/currency) writes do not bump pos_config_version yet — hooks
   cover Branch/TaxRule/Charge/TenderType/PosTerminal + explicit bumps on
   PIN set/clear. Effect is delayed pickup via heartbeat, never a wrong bundle.
   **Narrowed 2026-09-22 (A3):** ReceiptProfile joined the hooks, and a change
   to `restaurants.tax_registration_number` now bumps explicitly. Branding,
   currency and role edits are still the gap.
6. ~~**restaurants.tax_registration_number**: column shipped + delivered in the
   bundle, but UpdateRestaurantProfileRequest does not accept it yet — no
   authoring UI path this wave (settable via tinker/admin only).~~
   **CLOSED 2026-09-22 (A3).** `UpdateRestaurantProfileRequest` accepts
   `tax_registration_number` (nullable, ≤32, shape deliberately unvalidated so
   a half-typed number saves), the new Receipt details page authors it, and a
   change bumps `pos_config_version` because it rides the bundle twice — as
   `restaurant.tax_registration_number` and as every
   `receipt_profiles[].registration_number`.
7. **terminal_status 'stale' not computed** — heartbeat answers active|revoked
   only; 'stale' needs the site tier (POS-BE-026, deferred).
8. **POS-BE-009's self-registration endpoint subsumed by POS-BE-023** —
   terminals exist via provision+claim (Path A) or register (Path B); there is
   no separate POST /api/pos/terminals.
9. **Dine-in visit binding**: a POS order for a table with an OPEN TableVisit
   locks and joins it; the POS never creates visits (that stays QR-side).
10. **SUBSCRIPTION_LAPSED / CATALOG_STALE reserved, never emitted** (D2 agreed
    default; catalog staleness unenforced in v1).
11. **Line-level asserted price field is `lines[].unit_price_minor`** — used
    ONLY for the deleted-item name_snapshot fallback.

## Dev-DB drift gotcha (2026-09-04, from Agent 1)
The 000300 migration was EDITED (bcrypt column → pbkdf2 salt+hash pair) after
some local database.sqlite files had already run it, so an existing dev DB may
have the old shape (missing users.pos_pin_salt). Fix locally with a manual
ALTER or `php artisan migrate:fresh` (dev only!). **Prod unaffected — nothing
has been deployed; the migration lands there in its final form.**

## Post-wave additions (each under its own owner go)

| Date | Item | Status | Files (paths relative to apps/api) | Tests |
|---|---|---|---|---|
| 2026-09-22 | **A3 receipt profile in the bundle** (same owner go, item A3) | DONE | migrations/2026_09_22_000400, app/Models/ReceiptProfile.php, app/Services/ReceiptProfileService.php, Dashboard/ReceiptProfileController, Requests/Dashboard/UpdateReceiptProfileRequest, `receipt_profiles` block in PosBootstrapService, ReceiptProfile hooked in PosConfigVersion, `tax_registration_number` accepted in UpdateRestaurantProfileRequest + explicit bump in RestaurantProfileController, routes, lang en/ar; web: `apps/web/src/pages/dashboard/PosReceiptView.vue`, router, settings.config.js, `pos_receipt` + `nav.pos_receipt` in both locales | `tests/Feature/Pos/PosReceiptProfileTest.php` (10) |
| 2026-09-22 | **POS-BE-010 refunds** (owner go "hand A3 and A7 to xorder-cloud", item A7) | READY | migrations/2026_09_22_000100 + 000200, app/Models/{PosRefund,PosRefundLine,PosRefundTender}.php, app/Services/PosRefundService.php, Pos/RefundController, Requests/Pos/StoreRefundRequest, Resources/PosRefundResource, + `client_line_id` through StorePosOrderRequest → PosPricingEngine → PosOrderService → PosOrderResource, `settlementStatusFrom()` on PosOrderService, `cash_refunds` in PosShiftService, `$series` on InvoiceSequenceService, routes, lang en/ar | `tests/Feature/Pos/PosRefundsTest.php` (19) |

**The A7 design point, settled.** A cloud till could not upload a refund at all
because `outbox_drain.dart` needs platform order-item ids it has never seen. The
fix is `order_items.client_line_id`: the till stamps its own key on each order
line, the platform stores it verbatim under `unique(order_id, client_line_id)`,
and a refund addresses lines by `(order client_transaction_id, client_line_id)`.
It is excluded from the idempotency hash on purpose — it carries no money, so a
till that starts sending it must not collide with an order it already delivered.
**Recommended value is the till's local `pos_order_lines.id` as a string**, not
`TicketLine.key`: `TicketEngine` merges only lines that are draft + same key +
same note, so one order can genuinely hold two rows with the same `line_key`
(and `_insertLines` already collapses them into one map entry — a latent
ambiguity on the till, reported to `pos-dev`).

**A3, where it is authored and why.** A dedicated page under Settings → Point
of sale (`Receipt details`), not the branch form: a receipt profile is a POS and
e-receipt concern, the Branches page is shared with tenants that never bought
the till, and the money config next door is the established home for "platform
authors, till reads". It reuses `settings.view` / `settings.update` rather than
minting a `pos.receipt_profile` capability — the legal identity on a slip is the
same class of fact as `restaurants.tax_registration_number`, which
`settings.update` already authors, and a new checkbox would leave every role
that can edit tax unable to edit the header it prints on. **That is a judgement
call and the owner may reverse it**; reversing costs one enum case, one label
pair, and a grant on every existing role.

**OrderStatus decision (A7).** `OrderStatus` stays `NEW | COMPLETED |
CANCELLED`. Refund state is carried by the derived `settlement_status`, which
now answers `PAID | UNPAID | PARTIALLY_REFUNDED | REFUNDED` using the till's
own `paymentStatusFromSums` rule. `VOIDED` (named in the 2026-09-02 §010 text)
and `PARTIALLY_PAID` are deliberately never emitted — the first is a property
of the refund (`kind: "void"`), the second would change an existing wire value.

## Notes for a successor
- POS error envelope = App\Exceptions\PosApiException rendered via its own
  render(); ValidationException on /api/pos/* is mapped to VALIDATION_FAILED
  in bootstrap/app.php.
- Idempotency = unique (restaurant_id, client_transaction_id) per aggregate +
  payload_hash comparison (sha256 of the money-bearing fields, fixed order);
  replays serialise the STORED record through the same resource → identical
  bodies. Replay is 200, first write 201, never 409.
- Invoice numbers are assigned under lockForUpdate inside the order
  transaction (InvoiceSequenceService); replays read the stored number.
- One open shift per terminal is enforced under a lock on the terminal row.
- Deferred from this wave: POS-BE-004, 010, 012 (delta params), 014, 017,
  018, 021, 025, 026, 027 (extra claims), 028, and all web dashboard UI for
  terminals/money-config/PIN.

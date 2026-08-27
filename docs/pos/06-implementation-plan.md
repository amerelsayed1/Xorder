# 06 — Implementation Plan

**Author:** Agent 1 · **Date:** 2026-08-25

Estimates are for one full-time developer. **Phases 1–5 and 7 need no backend
change**, which is the point: Agent 2 can stay in analysis-only mode for roughly
two months without blocking a single day of POS work.

Legend — 🟢 no backend needed · 🟡 works on fakes, needs backend to ship
· 🔴 blocked without backend.

---

## Phase 1 — Foundation 🟢 · ~4 days

Desktop shell and the spine everything hangs off.

- `pubspec.yaml`: the dependency set from `04` §4
- `core/money` — `Money`, `Currency`, half-up rounding *(money before UI, deliberately)*
- `core/result` — `Result<T>`, sealed `Failure`
- `core/config`, `core/logging` (redacting), `core/utils/arabic_digits`
- `core/database` — SQLite open + versioned migration runner + v1 schema
- `core/network` — dio client, interceptors, status→failure mapping
- `core/ui` — design tokens seeded from `restaurant.brand_color`, buttons,
  numeric keypad, product tile, cart row
- `core/l10n` — en/ar ARB, RTL wiring
- `app/` — router with the guard chain, desktop shell, `window_manager`
- Riverpod root, `POS_FAKE` flavour switch

**Exit:** app launches on macOS and Windows at 1280×800, routes through
setup → login → an empty selling screen, in both LTR and RTL.
**Tests:** `Money` arithmetic, rounding boundaries, Arabic-digit normalisation,
migration runner idempotence.

---

## Phase 2 — Authentication & session 🟡 · ~4 days

- Setup screen: API URL, restaurant slug, branch, terminal name; `terminalId` minted
- Login screen (username + password + slug), full keyboard flow
- `AuthRepository` → `Api` + `Fake`; token in secure storage
- `SessionNotifier`, `PermissionSet` from `capabilities[]`
- Branch selection / binding; lock screen (POS-R007)
- 401 handling that pauses sync without ending the session (POS-R009)

**Backend:** none — `auth/login`, `auth/me`, `dashboard/branches` all exist today.
Only `POS-BE-002` (POS capability verbs) and `POS-BE-005`
(`supported_order_types`) are wanted, and both degrade gracefully.
**Exit:** real login against a running `apps/api`, permissions gating visible UI.

---

## Phase 3 — POS core 🟡 · ~8 days

- `CatalogRepository` → `Api` + `Local` + `Fake`; SQLite cache with `synced_at`
- Category rail with `availability_hours` honoured
- Product grid (photo/dense per `menu_layout`), virtualised for 2,000 items
- Search: AR + EN simultaneous, ≤100 ms, debounced, focus-stealing keystrokes
- Barcode input path (inert until `POS-BE-004`)
- Item configuration dialog: variants, modifiers, required/max-select, notes
- Cart panel: lines, qty, remove + undo, per-line note
- Hold / resume, persisted to SQLite
- Order type selector driven by branch config; table picker from `tables/live`

**Backend:** reads existing endpoints unchanged. `POS-BE-003` (auto-applied option
groups) and `POS-BE-004` (barcode) improve it; neither blocks.
**Exit:** a cashier can build a correct cart from the real catalog, offline.

---

## Phase 4 — Calculations 🟢 · ~5 days

The most important week in the project.

- `cart_engine.dart`: variant replacement, modifier stacking, line discount,
  order discount, charges, inclusive/exclusive tax, multi-tax, rounding, clamps
- `PricingContext` from server config, with read-only local fallback until `POS-BE-013`
- Price override with reason, gated on `pos.price_override`
- Discount dialogs (percent / fixed) gated on `pos.discount`
- **Table-driven unit tests to ≥95 % branch coverage** (POS-R079)

**Exit:** every case in POS-R079 green. No UI work counts as done in this phase.

---

## Phase 5 — Checkout, payment, receipt 🟡 · ~7 days

- Order review screen
- Tender selection from `TenderType` config; quick-cash buttons
- Split and partial payment; change due; keypad-first entry
- `clientTransactionId` minted per order and per payment
- Durable write **before** the UI advances (POS-R123) — the crash-safety commit
- `ReceiptDocument` builder + on-screen preview
- Order envelope assembled with `asserted_totals`; reconciliation dialog on mismatch

**Backend:** 🔴 to actually take money — `POS-BE-006`, `-007`, `-008`.
Until then it runs end-to-end on `FakeOrdersRepository`, which is enough to
validate the whole flow and the receipt.
**Exit:** full checkout on fakes, receipt rendered, order durable in SQLite.

---

## Phase 6 — Shifts & cash 🟡 · ~5 days

- Open shift with opening float; hard gate on selling
- Current-shift summary (sales, discounts, tax, tender breakdown)
- Cash in / cash out with reasons
- Close shift: expected vs counted, denomination counter, variance + reason
- X and Z reports, printed
- Everything works offline and queues (POS-R146)

**Backend:** 🔴 `POS-BE-009`.
**Exit:** a full offline day — open, sell, cash movements, close, Z report.

---

## Phase 7 — Offline & sync 🟢 · ~7 days

Built against the local queue and a stub endpoint; nothing here waits on a
finalised contract.

- `sync_queue` table + `SyncEngine`: causal ordering, concurrency cap,
  backoff with jitter, 401/409/422 handling, dead-letter
- Probe-based `ConnectivityService` (`03` §6)
- Incremental catalog sync path (falls back to full pull until `POS-BE-012`)
- Sync status indicator + queue inspector + dead-letter review + reverse
- Startup recovery; close-with-pending warning
- **Chaos tests:** kill mid-flight, 500 storm, timeout-then-success (the
  ambiguous case), token expiry mid-queue, duplicate replay

**Exit:** simulated 6-hour outage with 200 orders drains with zero loss and zero
duplicates.

---

## Phase 8 — Hardware 🟡 · ~6 days

- `PrinterService` + `NetworkEscPosPrinter` (TCP:9100)
- Receipt layout: 58 mm and 80 mm, Arabic-shaping verified on real paper
- Kitchen tickets with category→printer routing
- Print queue with retry + banner (POS-R106)
- Cash drawer kick
- Printer settings + test print
- `BarcodeScannerService` over raw keyboard events

**Exit:** receipt and kitchen ticket print on real hardware from both platforms.

---

## Phase 9 — Advanced 🟡 · ~7 days

- Order history, search, reprint (audited)
- Returns / refunds UI: find order, select lines, reason, supervisor override
- Customer create + order history
- Shift/sales reports at the till
- Settings: shortcuts remap, diagnostics, log export
- Packaging: signed macOS build, Windows installer, auto-update decision

**Backend:** 🔴 refunds need `POS-BE-010`.

---

## Sequenced summary

| Phase | Days | Backend | Deliverable |
|---|---|---|---|
| 1 Foundation | 4 | 🟢 | Shell runs on both platforms |
| 2 Auth | 4 | 🟡 | Real login, permissions |
| 3 POS core | 8 | 🟡 | Correct cart from real catalog |
| 4 Calculations | 5 | 🟢 | Money is provably right |
| 5 Checkout | 7 | 🔴 to ship | Full flow on fakes |
| 6 Shifts | 5 | 🔴 | Offline day, cash-up |
| 7 Offline/sync | 7 | 🟢 | Zero-loss queue |
| 8 Hardware | 6 | 🟡 | Real printing |
| 9 Advanced | 7 | 🔴 | Refunds, history, packaging |
| | **~53 days ≈ 11 weeks** | | |

**Backend-independent portion: phases 1, 3, 4, 7 plus most of 2 and 5 — roughly
7 of those 11 weeks.**

---

## Critical path & the one thing that matters

```
POS-BE-006 (authenticated, server-priced order creation)
    └── depends on order_items.menu_item_id existing at all
            └── which is a schema change to a LIVE table
```

`order_items` today stores only a `name` string. Until it carries `menu_item_id`,
the server cannot re-price a POS order, cannot deduct stock, and cannot report on
products honestly. Everything in Phases 5, 6 and 9 sits behind it.

It is also the change with the **largest independent payoff**: it fixes product
reporting for the existing QR product regardless of whether the POS ever ships.

If the owner approves exactly one backend item, it should be that one.

---

## Working agreement

- Agent 1 implements the Flutter app continuously and does **not** wait for
  backend approval (per the brief).
- Agent 1 treats no proposed contract as final. Repository interfaces + fakes are
  the insulation.
- Integration happens only when Agent 2 marks a requirement `READY` in
  `docs/coordination/BACKEND_TO_POS.md`. Adopting a `READY` contract is a
  provider-override diff, not a rewrite.
- New backend needs discovered mid-build get a new `POS-BE-xxx` entry in
  `POS_TO_BACKEND.md` — never an assumption baked quietly into client code.
- Agent 1 makes **no** change of any kind to `xorder-new/`.

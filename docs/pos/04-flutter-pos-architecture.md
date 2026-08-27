# 04 — Flutter POS Desktop Architecture

**Author:** Agent 1 · **Date:** 2026-08-25
**Flutter 3.47 / Dart 3.13** · Windows 10+ · macOS 13+

---

## 1. Principles

1. **The cart engine is pure Dart.** No `flutter` import, no I/O, no clock, no
   locale. It is the only code in the app where a bug costs money, so it is the
   only code that can be exhaustively tested without a widget tester.
2. **The UI depends on interfaces, never on HTTP.** Every data source is a
   repository interface with at least two implementations — real and fake. This
   is what lets Phases 1–5 ship while the backend is in analysis-only mode.
3. **One state solution, one DI solution.** Riverpod is both. Adding `get_it`
   alongside it would mean two lifetimes to reason about and no gain.
4. **No codegen in the critical path.** No `build_runner`, no `freezed`, no
   `json_serializable`, no `drift`. Hand-written `fromJson`, hand-written SQL
   migrations. The tradeoff is deliberate: more typing once, versus a generated
   layer between a developer and the money path plus a build step that can rot.
5. **Money is `Money`.** Integer minor units and a currency. `double` never
   appears in a monetary type, a database column, or a wire field the POS authors.
6. **Errors degrade a feature, never the till.** Any failure outside the sale
   path is caught, logged, surfaced, and stepped over.

---

## 2. Layering

```
        ┌──────────────────────── presentation ─────────────────────────┐
        │  screens · widgets · dialogs · shortcuts · theme · l10n       │
        │  reads state, dispatches intent — no business rules           │
        └───────────────────────────┬──────────────────────────────────┘
                                    │ Riverpod providers
        ┌───────────────────────────▼──────────────────────────────────┐
        │                        application                            │
        │  Notifiers / controllers: cart, checkout, sync, shift, auth   │
        │  orchestrates domain + repositories; owns no rules itself     │
        └───────────────────────────┬──────────────────────────────────┘
                                    │
        ┌───────────────────────────▼──────────────────────────────────┐
        │                          domain                               │
        │  entities · value objects (Money) · CART ENGINE               │
        │  repository INTERFACES · failures                             │
        │  ZERO Flutter dependencies. 100% unit-testable.               │
        └───────────────────────────┬──────────────────────────────────┘
                                    │ implements
        ┌───────────────────────────▼──────────────────────────────────┐
        │                           data                                │
        │  DTOs · api client (dio) · SQLite DAOs · secure storage       │
        │  repository IMPLEMENTATIONS (Api / Local / Fake)              │
        └──────────────────────────────────────────────────────────────┘
```

Dependencies point **inward only**. `domain` imports nothing from `data` or
`presentation`. Enforced by lint (§12) and by the fact that `domain` has no
`flutter` import at all — a mistake fails compilation in the pure-Dart test target.

---

## 3. Directory structure

Feature-oriented, with the layers inside each feature. Nothing pre-existing
constrains this — the app is greenfield.

```text
lib/
  main.dart                      # bootstrap only
  app/
    app.dart                     # MaterialApp.router, theme, locale, Directionality
    router.dart                  # go_router; auth/shift/setup redirects
    shell.dart                   # desktop shell: header, sync indicator, shortcuts
  core/
    config/                      # AppConfig, env, build flavour
    database/
      database.dart              # sqflite_common_ffi open + PRAGMA
      migrations.dart            # ordered, versioned migration list
      dao/                       # hand-written DAOs
    network/
      api_client.dart            # dio + interceptors (auth, locale, terminal, idempotency)
      api_exception.dart         # maps status → typed failure
      connectivity.dart          # probe-based ConnectivityService
    money/
      money.dart                 # Money value object (int minor units)
      currency.dart              # code + exponent, mirrors App\Enums\CurrencyEnum
      rounding.dart              # half-up, applied once at the boundary
    result/
      result.dart                # Result<T> — Ok | Err. No exceptions across layers.
      failure.dart               # sealed failure hierarchy
    logging/
      logger.dart                # levelled, redacting, file sink
    storage/
      secure_store.dart          # token only
      device_store.dart          # terminalId, device settings
    l10n/
      app_strings.dart           # hand-written en/ar + LocalizationsDelegate
    ui/                          # design system: tokens, buttons, keypad, tiles
    utils/
      arabic_digits.dart         # ٠١٢ → 012  (Dart port of packages/ui/enDigits.js)
      debouncer.dart
  features/
    setup/                       # first-run device configuration
    auth/                        # login, session, permissions, lock screen
    branch/                      # branch + terminal binding
    catalog/                     # categories, items, options, search, cache
    cart/                        # cart state + CART ENGINE (domain/)
    checkout/                    # order review → tender → receipt
    payments/                    # tender types, split, change
    customers/
    orders/                      # history, reprint, resume
    shifts/                      # open, cash in/out, close, X/Z
    refunds/
    printing/                    # PrinterService + implementations
    sync/                        # queue, engine, status UI, dead-letter inspector
    settings/
  test/  ── mirrors lib/, with test/features/cart/ carrying the weight
```

Inside a feature: `domain/` · `data/` · `application/` · `presentation/`.
A feature never imports another feature's `data/` or `presentation/` — only its
`domain/`. Cross-feature coordination happens through providers.

---

## 4. Chosen packages and why

| Concern | Package | Why this one |
|---|---|---|
| State + DI | `flutter_riverpod` | Compile-safe, testable by provider override, no context needed, no second DI container. Overrides are how a whole screen runs against `Fake*` repositories in a test. |
| Routing | `go_router` | Declarative redirects express the real guard chain: not set up → setup; not authed → login; no open shift → shift screen. |
| HTTP | `dio` | Interceptors for auth, `X-Locale`, `X-POS-Terminal`, `Idempotency-Key`, and typed error mapping. |
| Local DB | `sqflite_common_ffi` + `sqlite3_flutter_libs` | Real SQLite on Windows and macOS, hand-written schema + migrations, no codegen. |
| Secrets | `flutter_secure_storage` | Keychain on macOS, DPAPI-backed on Windows. Token only. |
| Paths | `path_provider`, `path` | DB and log locations. |
| Window | `window_manager` | Minimum size, restore geometry, title. |
| Ids | `uuid` | `clientTransactionId`, `terminalId`. |
| Formatting | `intl` | Dates and number *formatting* only — never money arithmetic. |
| Localisation | `flutter_localizations` + a hand-written `AppStrings` | RTL and Material's own Arabic strings come from the SDK; the app's strings are a sealed `EnStrings`/`ArStrings` pair, so a missing translation is a **compile error** rather than a runtime fallback. No `gen-l10n` step. |
| Connectivity | `connectivity_plus` | A hint that feeds the probe; never the source of truth (see `03` §6). |
| Printing | `esc_pos_utils_plus` + raw sockets | ESC/POS bytes over TCP works identically on both platforms from pure Dart. |
| Test | `flutter_test`, `mocktail` | Riverpod overrides cover most of it; `mocktail` for the rest. |

**Deliberately excluded:** `freezed`, `json_serializable`, `drift`, `get_it`,
`bloc`. Each would add a build step or a second way to do something the chosen
set already does.

---

## 5. The cart engine

`lib/features/cart/domain/cart_engine.dart` — pure functions over immutable
inputs. This is the architectural centre of the app.

```dart
/// Deterministic. No clock, no locale, no I/O. Same input → same output.
CartTotals computeTotals(CartState cart, PricingContext ctx);

final class PricingContext {
  final Currency currency;
  final List<TaxRule> taxRules;
  final List<ChargeRule> charges;
  final OrderType orderType;
  final int? branchId;
}

final class CartTotals {
  final List<LineTotals> lines;
  final Money subtotal;       // Σ line.net
  final Money orderDiscount;
  final Money taxableBase;
  final Money charges;
  final List<TaxLineTotal> taxLines;
  final Money inclusiveTax;   // extracted, does NOT increase total
  final Money exclusiveTax;   // added
  final Money rounding;
  final Money total;
  final Money paid;
  final Money remaining;      // max(0, total - paid)
  final Money change;         // max(0, paid - total)
}
```

Order of operations, fixed and tested (`02` §4.2):

```
base = variantOption?.effective ?? item.effective     // variant REPLACES
gross = (base + Σ nonVariantOption.effective) × qty
net   = gross − lineDiscount                          // clamped ≥ 0
subtotal    = Σ net
taxableBase = subtotal − orderDiscount                // clamped ≥ 0
charges     = Σ (percent of taxableBase | fixed)
tax         = Σ over (taxableBase + taxableCharges)
total       = taxableBase + charges + exclusiveTax + rounding
```

**Rounding happens once**, half-up, where a percentage becomes a money amount.
Intermediates stay integer.

`Money` invariants:

- constructed only from `Money.minor(int, Currency)` or a parsed decimal string
- arithmetic across differing currencies throws — it is a programming error
- `percentBp(int basisPoints)` for every rate, so `14%` is `1400`, never `0.14`
- no `toDouble()` exists on the type

---

## 6. State management

Riverpod, hand-written providers (no `riverpod_generator`).

```dart
// Infrastructure
final databaseProvider          = FutureProvider<PosDatabase>(...);
final apiClientProvider         = Provider<ApiClient>(...);
final connectivityProvider      = StreamProvider<ConnectivityState>(...);

// Repositories — the seam. Overridden with Fake* in tests and in fake mode.
final authRepositoryProvider    = Provider<AuthRepository>(...);
final catalogRepositoryProvider = Provider<CatalogRepository>(...);
final ordersRepositoryProvider  = Provider<OrdersRepository>(...);
final shiftsRepositoryProvider  = Provider<ShiftsRepository>(...);

// Session
final sessionProvider    = NotifierProvider<SessionNotifier, SessionState>(...);
final permissionsProvider= Provider<PermissionSet>((ref) => ...);

// Selling
final cartProvider       = NotifierProvider<CartNotifier, CartState>(...);
final cartTotalsProvider = Provider<CartTotals>((ref) =>
    computeTotals(ref.watch(cartProvider), ref.watch(pricingContextProvider)));

// Sync
final syncEngineProvider = NotifierProvider<SyncEngine, SyncStatus>(...);
```

`cartTotalsProvider` derives rather than stores. There is exactly one place
totals are computed, and no path where a stored total can drift from its cart.

`CartState` is immutable; every mutation returns a new instance. That is what
makes undo (POS-R029) a one-liner and makes a cart trivially serialisable for
hold/resume and crash recovery.

---

## 7. Repository pattern & the fake-first workflow

```dart
abstract interface class OrdersRepository {
  Future<Result<CreatedOrder>> createOrder(CreateOrderRequest request);
  Future<Result<CreatedOrder>> fireRound(FireRoundRequest request);
  Future<Result<List<OrderSummary>>> history(OrderHistoryQuery query);
  Future<Result<OrderDetail>> byId(String clientTransactionId);
}
```

Three implementations per repository:

| Impl | Role |
|---|---|
| `ApiXRepository` | Real HTTP. Written the moment the contract is `READY`. |
| `LocalXRepository` | SQLite read-through cache + write-to-queue. The offline path. |
| `FakeXRepository` | Deterministic in-memory data seeded from `assets/fake/*.json`. **Ships in the app** behind `--dart-define=POS_FAKE=true`, not only in tests. |

`OfflineFirstOrdersRepository` composes Local + Api: writes go to SQLite and the
queue synchronously and return immediately; the sync engine drains asynchronously.
The UI awaits durability, never the network.

**This is the mechanism that makes Agent 1 independent of Agent 2.** A full
demo — login, catalog, cart, checkout, receipt preview, sync indicator — runs
today with `POS_FAKE=true` and no backend at all.

---

## 8. Routing & guards

```dart
GoRouter(
  redirect: (ctx, state) {
    if (!deviceConfigured)      return '/setup';
    if (!authenticated)         return '/login';
    if (locked)                 return '/lock';
    if (!hasOpenShift && state.matchedLocation.startsWith('/pos')) return '/shift/open';
    return null;
  },
  routes: [ /setup /login /lock /shift/open /pos /pos/checkout
            /orders /orders/:id /customers /shift /settings /sync ],
);
```

`/pos` is the home route and the app returns to it after every completed action.
A cashier is never more than one `Esc` from the selling screen.

---

## 9. Printer abstraction

```dart
abstract interface class PrinterService {
  Future<Result<void>> printReceipt(ReceiptDocument doc);
  Future<Result<void>> printKitchenTicket(KitchenTicket ticket, PrinterTarget target);
  Future<Result<void>> openCashDrawer();
  Future<Result<List<PrinterTarget>>> discover();
  Future<Result<void>> testPrint(PrinterTarget target);
}
```

- `ReceiptDocument` is a **rendering-free value object** — sections, lines and
  `Money` values. Checkout builds it; it knows nothing about paper width or ESC/POS.
- Implementations: `NetworkEscPosPrinter` (v1, TCP:9100), `SpoolerPrinter`,
  `UsbEscPosPrinter`, `NoopPrinter` (dev/preview).
- **Print jobs are queued and retried like sync operations.** A dead printer
  produces a banner and a "print again" button, never a blocked sale (POS-R106).
- Kitchen routing maps `category.id → PrinterTarget` in local device settings.

Barcode is the same pattern: `BarcodeScannerService` over a raw-keyboard listener,
so a USB HID scanner and a future serial scanner are one interface.

---

## 10. Error handling

```dart
sealed class Failure {}
final class NetworkFailure   extends Failure {}   // retryable
final class AuthFailure      extends Failure {}   // 401 → pause sync, keep selling
final class ForbiddenFailure extends Failure {}   // 403 + code
final class NotFoundFailure  extends Failure {}   // 404 — may mean "not your tenant" (C-6)
final class ValidationFailure extends Failure {}  // 422 → dead-letter
final class ConflictFailure  extends Failure {}   // 409 → resolve by clientTransactionId
final class ServerFailure    extends Failure {}   // 5xx → retry
final class LocalStoreFailure extends Failure {}  // SQLite — the only true emergency
final class PrinterFailure   extends Failure {}   // never blocks a sale
```

`Result<T>` at every layer boundary; exceptions never cross one. A `try/catch`
that swallows without logging fails review.

`LocalStoreFailure` is the one failure that stops the till, because it means
durability is no longer guaranteed — and selling without durability is the one
thing worse than not selling.

---

## 11. Logging

Levelled (`trace…fatal`), console in debug, rolling file in release at
`<applicationSupportDirectory>/xorder_pos/logs/`, 7-day retention, exportable
from Settings → Diagnostics.

A **redacting** formatter strips `Authorization`, `token`, `password` and payment
references before anything is written (POS-R226). Every sync attempt logs
`clientTransactionId`, endpoint, status and attempt number — that log is the first
thing anyone reads when a transaction is disputed.

---

## 12. Testing

| Layer | Approach | Bar |
|---|---|---|
| Cart engine | Pure unit tests, table-driven | **≥ 95 % branch** (POS-R224) |
| Money / rounding | Unit + property-style edge sweeps | 100 % of arithmetic |
| Repositories | Fake HTTP + in-memory SQLite | happy path + every failure branch |
| Sync engine | Simulated clock, injected failures | ordering, backoff, dead-letter, 409 replay |
| Notifiers | `ProviderContainer` with overrides | state transitions |
| Widgets | `testWidgets`, LTR **and** RTL | selling screen, checkout, dialogs |
| Shortcuts | Key-event tests | every binding in POS-R051 |

`analysis_options.yaml` adds `avoid_double_and_int_checks`, strict
`implicit-casts: false`, and a custom import rule keeping `domain/` free of
`package:flutter`.

---

## 13. Desktop specifics

- `window_manager`: minimum 1280×800, geometry restored, title carries branch +
  terminal so a multi-till floor can tell windows apart.
- Global `Shortcuts`/`Actions` at the shell so bindings work from any screen, with
  a `FocusScope` rule that a bare keystroke outside a text field routes to search.
- `sqlite3_flutter_libs` for the bundled SQLite on both platforms.
- macOS entitlements: network client (API + network printers), and **no** sandbox
  file access beyond application support.
- Windows: no admin rights required; all state under `%APPDATA%`.
- Release: `flutter build macos` / `flutter build windows`; signing and installer
  packaging are a Phase 9 concern.

---

## 14. What this architecture buys

- The money path is testable without a device, a server, or a printer.
- The backend can stay in analysis-only mode indefinitely without stalling POS work.
- Swapping a fake for a real repository is a one-line provider override, so
  "the backend is ready" is a small, reviewable diff — not an integration project.
- Offline is not a mode bolted on later: the write path goes through SQLite and a
  queue from the first order the app ever takes.

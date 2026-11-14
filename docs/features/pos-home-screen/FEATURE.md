# POS home screen: one button per enabled order type — pos-home-screen

Status: built, uncommitted · 2026-10-26 · Source: the owner, 2026-10-26: "I was thinking to make new home screen to have button for Floor - Take away - etc what ever enable from the backoffice" · Verified against: xorder-pos `a6f5fe5` + 148 uncommitted files (not this feature's), xorder-cloud `06bc8e3` (not touched)

## 1. Summary
After a shift is open, the till shows a home screen with one big button for each order type the back office has enabled — Floor (tables) for dine-in, Take away, and so on — and tapping one starts selling that way. What shows follows the back office; nothing is hard-coded.

## 2. Why
Today the choice of how an order is sold is split: Start goes straight to the Floor (or to the sale when nothing is seated), and a counter sale is a "sell without table" link on the Floor or the small mode switch in the sale screen's top bar. A cashier at a restaurant that does tables, takeaway and delivery has no single place to say what kind of order they are starting.

## 3. Goal and success
A cashier opens a shift, sees exactly the ways this branch sells, taps one and is selling that way; a branch that sells one way never sees an extra screen.

## 4. Users, roles and permissions
Whoever is signed in at the till (cashier and up). No new permission and nobody is newly allowed or refused anything: Home only routes to screens that exist. Which buttons appear is set in the back office by whoever may edit order types today (not changed by this feature).

## 5. Today (verified in source, `apps/xorder-pos`)
| Fact | Where |
|---|---|
| The order types are `dineIn`, `takeaway`, `delivery`, `driveThru`; a closed enum. | `lib/domain/models/ticket.dart:14-18` |
| What a branch may sell and in what order: `branchOrderTypesProvider` = the restaurant's active types (its own sort order) ∩ the branch's `supportedOrderTypes`, never empty. It is already what the sale screen's mode switch shows. | `lib/app/providers.dart:1414-1435`, `lib/features/sale/sale_screen.dart:620` |
| Which types are seated: `OrderTypeRules.requiresTable`, `hasSeating`; each type has an English and an Arabic configured name (`displayName`). | `lib/domain/models/order_type_config.dart:30-110` |
| Where the owner switches them: the back office's order-types pane and Settings; turning a type off hides it on the till. | `management_order_types_pane.dart`, `providers.dart:1405-1413` (comment) |
| Start: "Start shift" / "Resume shift" opens or resumes the shift, then `onStart`. | `lib/features/start/start_screen.dart:63-76` |
| `onStart` goes to the Floor; the router sends the Floor to the sale when nothing is seated. | `lib/app/router.dart:181`, `:97` |
| The Floor picks a table (or "sell without table"), then the sale. | `router.dart:202-257`, `floor_screen.dart:15-33` |
| Sale: the top bar's mode switch changes the type (`setOrderType`); a one-type branch shows a label instead. | `lib/features/sale/widgets/pos_top_bar.dart` (mode switch), `providers.dart:1585-1600` |
| Signed-out guard: sale and floor with a shift open and nobody signed in go to Lock. | `router.dart:48-53` |
| Lock, once unlocked, goes to the sale; Close shift on the sale goes to Start. | `router.dart:195`, `:288` |
| A "Home" exists in the **back office** (the dashboard pane); this feature is a different screen. | `docs/features/back-office-navigation/NAVIGATION_INVENTORY.md:41` |
| How a **cloud** till receives its order types (bundle) vs an offline one (local database): not traced. **UNVERIFIED**; Home reads the same provider as the sale screen, so both behave as the sale screen does. | — |
| Existing tests that touch these routes: `sale_flow_test`, `sign_in_test`, `idle_lock_test`, `order_type_rules_test`, `order_types_schema_test`. | `test/` |

## 6. Scope
**In:** a Home screen and its route; one button per enabled type; the route from Start; skipping Home for a one-type branch; the sign-in guard for Home; tests; docs.
**Out:** any change to order types, the back office's editor, the Floor or the sale screen's behavior; new order types; payment, tax or ticket rules; customer or address capture for delivery (nothing reads `requiresCustomer`/`requiresAddress` yet); orders, lock or close-shift buttons on Home; a Home button on the sale screen (see §13).

## 7. Behavior and business rules
- **BR-1** Home appears after the shift is open or resumed. Start stays the shift gate unchanged (licence block, PIN, float).
- **BR-2** One button per type in `branchOrderTypesProvider`, in its order, labelled with the type's configured name in the till's language. Nothing else is on the screen except what identifies the till.
- **BR-3** A type that needs a table (dine-in by default) opens the Floor. Every other type opens the sale with the ticket set to that type and no table.
- **BR-4** If the branch sells **one** type, Home is not shown: the cashier goes straight where Start sent them before (Floor if that one type is seated, otherwise the sale with that type).
- **BR-5** The list follows the back office live: a type turned off disappears, one turned on appears, without restarting.
- **BR-6** Home is a selling screen for the sign-in guard: with a shift open and nobody signed in it goes to Lock, as the sale and Floor do.
- **BR-7** Setting the type uses the ticket's existing `setOrderType`, so every rule of switching type (detaching a table, the engine's checks) is unchanged.
- **BR-8** No money, tax, discount, payment or order-state rule changes.
- **BR-10** Escape, one step back: **Home → Start**; **floor → Home** (Start for a one-way branch, as its back button); **sale → the floor** for a seated order type, otherwise **Home**, and nothing on a branch that has neither; **Orders** and the **licence screen** → their own back button. On the sale screen a typed search is cleared first, and Escape inside any other text box means "stop editing", not "leave". A seated ticket with items is parked on its table on the way out; an unseated ticket stays in the cart. Lock and Start do nothing (Lock must not be skipped; Start is the root).
- **BR-9** *(added 2026-10-26 after the owner saw the flow unchanged)* When a shift is resumed with nobody signed in — the normal case after a restart — the sign-in guard sends the till to the lock screen first. Unlocking then returns to the screen the till was heading for (Home, the floor or the sale), not always to the sale. Pressing Lock at the till still returns to the sale.

## 8. Acceptance criteria
- **AC-1** Given two or more enabled types, when the shift is opened or resumed, then Home shows one button per enabled type, in the configured order, with the configured Arabic or English name. *Widget test.*
- **AC-2** Given a type is disabled in the back office or not supported by the branch, then it has no button; when it is re-enabled, it appears without a restart. *Widget test with the provider overridden and changed.*
- **AC-3** Given exactly one enabled type, then Start goes to the Floor (if seated) or to the sale with that type, and Home never shows. *Widget/router test.*
- **AC-4** Given a seated type, when its button is tapped, then the Floor opens and picking a table continues exactly as today. *Router test.*
- **AC-5** Given a non-seated type, when its button is tapped, then the sale opens with `ticket.orderType` equal to that type and no table. *Widget test.*
- **AC-6** Given a shift is open and nobody is signed in, when Home is reached, then the till shows Lock. *Router test (as `sign_in_test` does for the sale).*
- **AC-7** Given Arabic, then the buttons and the screen lay out right-to-left with no overflow at 1024×700. *Widget test.*
- **AC-8** Given a cloud till and an offline till, then both show Home from the same provider. *Widget test with both overrides.*
- **AC-9a** Given a shift is open and nobody is signed in, when Resume is pressed and the person unlocks, then Home shows (for a branch with a choice). *Router test.*
- **AC-9** Existing flows keep working: Start's shift gate and licence block, Lock → sale, Close shift → Start, the Floor's "sell without table". *The existing tests pass, updated only where a route they assert has moved.*
- **AC-10** How it looks and feels with real names and four types on a counter screen. *Needs a person.*

## 9. Edge cases and failure modes
- **Offline / slow database:** the provider falls back to the seeded four while loading; Home must not flash buttons that vanish (decide in the plan: wait for the first answer or accept the fallback — the sale screen's switch accepts it today).
- **Back office disables the type the open ticket uses:** the sale screen already handles it (`providers.dart:1585`); Home does not change that.
- **Restart mid-service:** the till comes back on Start (no PIN remembered), as today; resuming goes through Home like starting does.
- **Empty list:** cannot happen (`branchOrderTypesProvider` is never empty).
- **Very long names / four types:** buttons must not clip at the smallest window (1024×700) in Arabic.
- **Tenant and money:** no tenant data or money is touched; no API call.
- **Plan/licence limits:** none apply to Home; the licence still gates Start.

## 10. Impact
POS only. No cloud, API, contract (`docs/coordination/`), schema or migration change; no deploy ordering. New feature folder `lib/features/home/` (name to settle in the plan); `lib/app/router.dart` (a route, the guard, `onStart`); possibly one string. The existing tests that name routes (§5) may need a route updated. Docs: inventory row, this folder.

## 11. Dependencies, known gaps, risks
- Depends on `branchOrderTypesProvider`/`orderTypeRulesProvider` staying the source of truth.
- Risk: **no way back to Home from the sale screen** (owner's choice, §13) — after the first sale a cashier changes type with the top bar's switch; Home reappears only through Start (close shift) or a restart. If the owner wants a way back it is a small addition.
- Domain lens (`docs/domain/FOOD_SERVICE_DOMAIN.md` §2, §6): **restaurant** (tables + takeaway + delivery) gains the most; **café, food truck and cloud kitchen** (one way to sell) are protected by BR-4 and see no change. A venue with no tables never sees a Floor button because nothing it sells requires a table. Delivery is just a type here: no address or customer is asked (known gap, `FOOD_SERVICE_DOMAIN.md` §3).
- The work sits on 148 uncommitted files, among them `router.dart` and `start_screen.dart`, so it will be mixed with other unfinished work.

## 12. How it will be tested
Flutter widget and router tests (existing frameworks, no database): AC-1..8 each have one; AC-9 is the existing suites; AC-10 is a person's look at the running till. `flutter analyze` and the full `flutter test`.

## 13. Decisions and open questions
**Decided by the owner, 2026-10-26**
- **D-1** Home sits **after the shift opens**; Start stays the shift gate; a one-type branch skips Home.
- **D-2** Buttons carry the **back office's configured names**, in its order; a seated type opens the **Floor**, any other type opens a new sale of that type.
- **D-3** Home holds **only the order-type buttons** (no Orders, Lock or Close shift) and the sale screen gets **no Home button**. *(Amended 2026-10-26, below: the way back is the Escape key.)*
- **D-4 (2026-10-26)** **Escape is "back" in general: it does what a back button would, one step along the way here, and does nothing where there is nowhere to go back to.** Dialogs and sheets already close on Escape and keep doing so.

**Still open (suggestions, not asked for — defaults below if not answered)**
- **Q-1** Keyboard: number keys 1–4 pick a button and Enter picks the focused one, as the rest of the till is keyboard-first. Default: yes.
- **Q-2** ~~Coming back to Home after the first sale.~~ Resolved 2026-10-26: the Escape key (D-4), no on-screen Home button.
- **Q-3** While the order-type list is still loading, show the seeded four (as the sale screen does) or a short wait. Default: wait for the first answer, then show.

## 14. As built (2026-10-26)
Built as planned in `TECHNICAL.md`; see `CHANGELOG.md` and `TEST_REPORT.md`. Q-1 (keys 1–4) and Q-3 (wait for the configuration) were taken at their defaults; Q-2 stays as decided (no way back). AC-8 has no dedicated test and AC-10 needs a person.

## 15. Amended 2026-10-27 by `pos-signin-first-home` (supersedes where it differs; see that folder)
The owner moved sign-in out of "Start shift" and put the shift button on Home. These rules above are **replaced**:
- **D-1 / BR-1** Home no longer sits "after the shift opens". Start is now a **sign-in** (name and PIN, no drawer); Home is where somebody lands next, with **Start shift** (`shift.open`), the order types and **Close the day** (`day.close`), each shown only to a person who may.
- **BR-2 / BR-3** Unchanged while a shift is open. With **no** shift open the order-type buttons are shown but dead, with "Start a shift to sell."; a one-type branch shows only Start shift.
- **BR-4** A one-type branch skips Home **only when a shift is already open** (`afterSignIn`). With no shift it sees Home, which is where Start shift is. Starting a shift from Home goes straight to the sale or floor for a one-type branch.
- **BR-6** Home with **nobody signed in goes to Start** (never the lock screen). `needsSignIn` no longer includes Home; sale and floor keep it.
- **BR-9 / AC-9a** A restart with the shift still open: sign in at Start (PIN asked there), then Home. The lock screen is no longer on the resume path (Lock at the till and the idle lock are unchanged for the sale and floor).
- **D-4 (Escape)** On Home, Escape and the new **Sign out** button sign the person out and go to Start. The idle lock on Home also signs out and goes to Start.
- **AC-6** now reads: Given nobody signed in, when Home is reached, then the till shows Start.
Evidence: `lib/features/home/home_screen.dart`, `lib/app/router.dart` (`afterSignIn`, the Home redirect, `needsSignIn`), `lib/features/lock/idle_lock.dart`; tests `test/features/{home_screen,home_flow,signin_first_flow,sign_in,idle_lock}_test.dart`.

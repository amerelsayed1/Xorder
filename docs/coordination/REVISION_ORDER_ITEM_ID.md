# REVISION — Order line item name: freeze bilingual snapshot from item id

**Status:** DESIGN / PROPOSED · **Scope:** backend (`apps/api`) + web (`apps/web`) + POS contract note
**Owner decision being specced:** for orders, the POS sends the **item id, not the item name**. The
backend resolves the item by id at order-creation time and **freezes both `name_ar` and `name_en`**
onto the order line (a snapshot, so history stays accurate even if the item is later renamed or
deleted). The dashboard then displays the name by the current UI locale, with a defined fallback.

This doc is a spec only — no code here is applied. It does not edit any other coordination file.

---

## 0. Problem, verified in code

An order line stores a single snapshotted `name` string. That single string is chosen at
creation time and is effectively one language, so a POS order shows an English item name even when
the dashboard is switched to Arabic (and vice-versa). Menu items are bilingual (`menu_items.name_ar`
/ `name_en`), but only one of the two was ever persisted on the line.

Where this happens today:

| Layer | File / symbol | Current behaviour |
|---|---|---|
| POS ingest | `app/Services/PosOrderService.php` line 244, and the legacy `items` JSON projection lines 183–189 | stores `'name' => $line['name']` (single string) on `OrderItem` and on `orders.items` |
| Pricing (name source) | `app/Services/PosPricingEngine.php` lines 84 & 93 | resolves the item by `menu_item_id`, then sets one `name = $line['name_snapshot'] ?? ($item->name_en ?: $item->name_ar)` — **client snapshot wins, else EN-preferred single string** |
| Public/QR ingest | `app/Http/Controllers/Public/PublicOrderController.php` `recordRound()` line 278–293, and `orders.items` merge line 144–147 | stores `'name' => $line['name']` (diner-locale single string), **no `menu_item_id`** |
| Resources | `OrderRoundResource.php` L18, `PosOrderResource.php` L60, `OrderResource.php` L20 (`items` JSON) | expose only `'name'` |
| Dashboard | `apps/web/src/pages/dashboard/OrdersView.vue` `itemTitle()` L203, receipt sheet L441 | print `it.name` verbatim from `order.items` |

**Key nuance discovered:** the POS-BE-006 wire already carries `lines[].menu_item_id` (nullable) and
`lines[].name_snapshot` (`required_without:menu_item_id`) — see
`app/Http/Requests/Pos/StorePosOrderRequest.php` L46, L52. So the id is *already sent*; the pricing
engine *already resolves the item*. What is missing is that the backend collapses the resolved item
to **one** language and lets the client's `name_snapshot` override even the resolved case. This
revision keeps the id-driven resolution and instead **freezes both names from the resolved item**.

The problem statement's "the POS sends the name directly" is therefore slightly stale for the POS
path (it sends id + snapshot) but exactly true for the **public/QR path**, which sends only a name
and no id. The unification below covers both.

---

## 1. Schema change — `order_items` (additive, nullable)

Add two nullable snapshot columns; **keep `name` for back-compat** (historical rows and the
public/QR path continue to populate it). Production DB is live → additive-only, no backfill of live
rows, no `NOT NULL`, no data rewrite.

New migration (name e.g. `2026_09_2x_000000_add_name_ar_en_to_order_items_table.php`):

```php
public function up(): void
{
    Schema::table('order_items', function (Blueprint $table) {
        $table->string('name_ar')->nullable()->after('name');
        $table->string('name_en')->nullable()->after('name_ar');
    });
}

public function down(): void
{
    Schema::table('order_items', function (Blueprint $table) {
        $table->dropColumn(['name_ar', 'name_en']);
    });
}
```

- `menu_item_id` already exists (`2026_09_02_000100_add_menu_item_id_to_order_items_table.php`,
  nullable FK, `nullOnDelete`). No change needed there.
- **`OrderItem` model** (`app/Models/OrderItem.php`): add `name_ar`, `name_en` to `$fillable`
  (they are currently `forceFill`ed for the minor-unit columns, so either add to `$fillable` or keep
  `forceFill` — pick one and be consistent with how `menu_item_id`/`price_source` are written today,
  which is `forceFill`). Casts unchanged (plain strings).

**Legacy `orders.items` JSON projection** (`orders.items`, cast `array` on `Order`): the dashboard
renders from this array (see §5). Each element gains `name_ar` + `name_en` alongside the existing
`name`, so the display path can resolve by locale without a rounds join. `name` stays for
back-compat.

---

## 2. Backend order-creation logic

### 2a. Name source of truth (POS path — `PosPricingEngine::price()`)

Change the per-line name resolution so a **resolved** item freezes *both* languages from the item,
and the client snapshot is used only as a **fallback**:

- **Item resolves** (`$item !== null && ! $item->trashed()`):
  - `name_ar = $item->name_ar`
  - `name_en = $item->name_en`
  - legacy `name = $item->name_en ?: $item->name_ar` (kept for back-compat / non-locale consumers)
  - `price_source = 'server'` (unchanged)
  - The client's `name_snapshot` is **no longer preferred** over the resolved name — drop the
    `$line['name_snapshot'] ??` precedence for the resolved case. (Rationale: the whole point of the
    revision is that the *server* is the naming authority for resolvable items; the till's displayed
    string is advisory, not canonical.)
- **Item does NOT resolve** (`null`/trashed — deleted during an outage) — the fallback rule:
  - `name = name_ar = name_en = $line['name_snapshot'] ?? __('xorder.pos.unknown_item')`
    (i.e. the single POS-provided snapshot is written into *both* language slots so the display path
    always has something, in whatever language the till printed).
  - `price_source = 'client_asserted'` (unchanged), order flagged as today.

The engine's returned line array therefore gains `name_ar` and `name_en` in addition to the existing
`name`.

### 2b. Fallback rule when the id does not resolve — DECISION

**Accept the line using the optional POS-provided `name_snapshot` (do NOT reject).** This preserves
the existing, deliberate POS-BE-006 behaviour: *money was already taken at the counter*, so a line
whose `menu_item_id` was deleted during an outage must still be recorded (flagged
`price_source: client_asserted`), not refused. Rejecting would lose a real sale. This matches the
current contract (`MENU_ITEM_NOT_FOUND` is reserved for an id that *never existed in this tenant*;
deleted-during-outage uses the snapshot fallback — see BACKEND_TO_POS.md §006 L467 and the error
table L1568).

`StorePosOrderRequest` already enforces `name_snapshot` `required_without:menu_item_id`, so a line
with neither id nor name is a 422 at validation — no code change needed there.

Note the fallback is English-only today: the till sends a single `name_snapshot` = `Product.nameEn`
(see §7 gap 3), so an unresolved line's `name_ar` and `name_en` both hold that one string. Optional
POS follow-up: accept a `name_ar_snapshot` to restore bilingual fidelity on the fallback path.

### 2c. Persist both names (`PosOrderService::create()`)

- `OrderItem` write (currently L243–265): add `'name_ar' => $line['name_ar']`,
  `'name_en' => $line['name_en']` next to `'name' => $line['name']`.
- Legacy `orders.items` JSON projection (currently L183–189): add `name_ar` and `name_en` to each
  mapped element.

### 2d. Public / QR path — unify (`PublicOrderController`)

The public path currently stores only `name` (the diner-locale string from the menu SPA) and **no
`menu_item_id`**. To unify:

- **Preferred (fuller unification):** have the menu SPA send `menu_item_id` per line
  (`apps/menu`), and have `PublicOrderController::recordRound()` + the `orders.items` merge resolve
  the item and freeze `name_ar`/`name_en` exactly as the POS path does. This requires a public
  request-contract change (`StoreOrderRequest` currently validates `items.*.name` required, no id —
  see L47) and a menu-SPA change. **Flagged as a larger, separate change.**
- **Minimum (this revision):** without a menu-SPA change, write the single diner-provided `name`
  into **all three** columns on the public path (`name = name_ar = name_en = $line['name']`). The
  diner already saw the menu in one language; there is no second language to recover server-side
  without the id. This keeps the display path uniform (always has `name_ar`/`name_en`) and loses
  nothing that exists today. Recommended for this revision; the SPA-sends-id unification is a
  follow-up.

**Recommendation:** ship the **Minimum** for the public path now (uniform columns, zero SPA risk),
and track "menu SPA sends `menu_item_id`" as a separate coordination item so QR orders become truly
bilingual later. POS is the path that actually has the id today and gains the real benefit
immediately.

---

## 3. POS-BE-006 line-contract amendment (belongs in `docs/coordination/BACKEND_TO_POS.md`)

The wire request shape is **unchanged** — the line already carries `menu_item_id` (nullable) and
`name_snapshot` (optional, `required_without:menu_item_id`). This revision only tightens the server's
*use* of those fields and expands the **response**. Document as an amendment to §006:

**Request line (no change to accepted fields):**

```jsonc
"lines": [
  { "client_line_id": "L1",            // POS-BE-010, unchanged
    "menu_item_id": 101,               // the catalog item id (== menu_items.id); nullable
    "variant_option_id": 555,
    "option_ids": [710, 712],
    "quantity": 2,
    "note": "no onions",
    "name_snapshot": "Classic Burger",  // NOW: fallback only — used when menu_item_id
                                         // does not resolve. Ignored for naming when the
                                         // item resolves (server freezes name_ar/name_en
                                         // from the item). Still required_without menu_item_id.
    "unit_price_minor": 9500,           // asserted; used only in the client_asserted fallback
    "discount": { … }, "price_override": { … } } ]
```

**Response line (expanded):** each `lines[]` element gains `name_ar` and `name_en`; `name` is kept
for back-compat.

```jsonc
"lines": [
  { "id": 1, "menu_item_id": 101,
    "client_line_id": "L1", "refunded_quantity": 0,
    "name": "Classic Burger",          // back-compat (EN-preferred, or the snapshot fallback)
    "name_ar": "برجر كلاسيك",           // NEW — frozen from the item at creation
    "name_en": "Classic Burger",        // NEW — frozen from the item at creation
    "quantity": 2, "unit_price_minor": 9500,
    "line_total_minor": 19000, "price_source": "server" } ]
```

Note: on the `client_asserted` fallback, `name_ar == name_en == name == name_snapshot` (the single
string the till printed). The amendment text should say so explicitly.

---

## 4. Resource changes

Expose the two snapshot columns; keep `name` so nothing that reads it breaks.

- **`PosOrderResource.php`** (L53–67): in the `lines` map add `'name_ar' => $item->name_ar`,
  `'name_en' => $item->name_en` (keep `'name' => $item->name`).
- **`OrderRoundResource.php`** (L15–24): in the `items` map add `name_ar`, `name_en` (keep `name`).
- **`OrderResource.php`** (L20): `items` is the legacy JSON array read straight off `orders.items`.
  Once §2c writes `name_ar`/`name_en` into that JSON, the array carries them automatically — no
  transform needed. (Historical rows in that JSON lack the two keys → the frontend falls back to
  `name`, see §6.)

**Decision — expose raw columns, resolve on the client (not a server-locale-resolved single
`name`).** Reasons: (1) the dashboard is a bilingual SPA whose locale is a client concern and can be
toggled without refetching; a server-resolved single string would be wrong the instant the user
flips locale; (2) the app already resolves bilingual names client-side with the exact idiom
`locale === 'ar' ? name_ar || name_en : name_en || name_ar` (e.g.
`apps/web/src/pages/admin/RestaurantDetails.vue` L503, L925). Keep that idiom consistent.

---

## 5. Frontend — `apps/web` (`OrdersView.vue`) + receipt / live board

`OrdersView.vue` renders line names from `order.items` (the legacy JSON array) in two places:
`itemTitle()` (L203, used by the board summary `itemSummary()` L196 and the cell at L325) and the
receipt sheet (L438–445, `receiptOrder.items`). Both currently read `it.name`.

Add one locale resolver and route both through it:

```js
// mirrors the app-wide idiom (RestaurantDetails.vue L503)
function itemName(it) {
  const ar = it.name_ar, en = it.name_en
  const byLocale = locale.value === 'ar' ? (ar || en) : (en || ar)
  return byLocale || it.name || ''   // fallback to legacy single name (§6)
}
```

- `itemTitle(it)` → use `itemName(it)` instead of `it.name`:
  `return it.variant ? \`${itemName(it)} (${it.variant})\` : itemName(it)`.
- Receipt line title (L441): `{{ itemName(it) }}` instead of `{{ it.name }}`.
- The live board updates via the same list `load()` refresh — no separate socket path to touch; the
  reactive `locale` means a locale toggle re-renders names with no refetch.

If any other surface reads line names (e.g. a POS receipt reprint in `apps/web`, or `apps/menu`
order-status), apply the same `itemName()` resolver there. (Grep `\.name` against order/line render
sites before shipping.)

---

## 6. Back-compat (historical + public rows)

Every row created before this ships — and every public/QR row under the "Minimum" option — has
`name` populated and `name_ar`/`name_en` NULL (or, for public "Minimum", all three equal). The
display path must degrade gracefully:

- **Frontend:** `itemName()` above ends in `... || it.name || ''` — NULL `name_ar`/`name_en` fall
  through to the legacy `name`. No historical order renders blank.
- **Backend/resources:** expose `name_ar`/`name_en` as-is (may be null) plus `name`. Never assume the
  snapshot columns are present.
- **No backfill.** Live rows are not rewritten. `ReportService` name-matching (BE-A05) and any other
  `name`-based consumer keep working because `name` is retained on every path.
- **Deleted-item fallback** already fills all three with the snapshot string, so those lines are also
  never blank.

---

## 7. Do POS catalog ids reliably map to `menu_items.id`?

**Backend-side evidence (confirmed):** the catalog the till receives is built by
`app/Services/PosBootstrapService::catalog()`. Each catalog item is emitted with
`'id' => $item->id` (the real `menu_items.id`) **and** both `'name_en' => $item->name_en` /
`'name_ar' => $item->name_ar` (L225–228). Delivered via `GET /api/pos/bootstrap` (POS-BE-023,
**READY**); incremental sync is POS-BE-012 (APPROVED). Option groups/options and categories are
shipped keyed by their real backend ids the same way. So the id the till holds for a catalog item
*is* the backend `menu_items.id`, and the catalog is already bilingual on the device.

Corroboration on the server: `PosPricingEngine::price()` resolves lines with
`MenuItem::withTrashed()->whereIn('id', array_column($lines, 'menu_item_id'))` (L62) — i.e. it treats
the line's `menu_item_id` as a direct `menu_items.id` and already relies on that mapping today for
pricing. If the mapping were unreliable, current POS pricing would already be broken.

**POS-side evidence (confirmed by inspecting `xorder-pos`):** the cloud bootstrap seeder keeps the
platform id **verbatim** — `BootstrapSeeder._seedCatalog()` inserts `pos_products (id, …)` using the
bundle's `product.id` as the local primary key, and `_bumpSequences()` pushes local serials past the
max seeded id so locally-authored rows never collide. There is **no id-remapping table**, by design,
so a seeded line's `product.id` == `pos_products.id` == backend `menu_items.id`. The order-create
drain (`outbox_drain.dart` `lineJson()`) sends both `menu_item_id` (that id, or `null`) and
`name_snapshot`. The POS catalog is bilingual (`Product.nameEn` + `Product.nameAr`). Verdict for the
cloud path: **the mapping is reliable.**

**Flagged mapping gaps (from the same exploration):**
1. **Locally-authored catalog rows are NOT backend ids.** Rows created on the till — Excel
   `menu_import`, the back-office Menu pane, or any **branch-server / islanded** deployment (not built
   in Phase 1) — get **locally-assigned serial ids unrelated to `menu_items.id`**. A line referencing
   such an id would fail to resolve server-side and fall to the `name_snapshot` path. Today's cloud
   path is unaffected (catalog is platform-authored); flag it so branch-server work preserves the
   cloud id as the wire id.
2. **Open-price and combo lines send `menu_item_id = null` deliberately** (a negative synthetic id
   is used only for ticket-merge and must never reach the wire). These are never server-re-priceable
   or resolvable by id — they always take the `name_snapshot` fallback. Expected, not a bug.
3. **`name_snapshot` on the wire is English-only** — the till sends `line.product.nameEn` as the
   single `name_snapshot` (`postgres_orders_repository.dart`), even though its local catalog holds
   `nameAr` too. **Consequence for this revision:** on the fallback path (id null/unresolved) the
   Arabic name cannot be recovered server-side, so `name_ar` = `name_en` = the English snapshot. This
   is acceptable (rare, deleted-item/open-price only) but is the one place bilingual fidelity is lost.
   **Optional POS follow-up:** have the till also send `name_ar_snapshot` (from `Product.nameAr`) so
   the backend can freeze a real Arabic name on unresolved/open-price lines. Track as a separate
   POS-BE contract note; not required to ship this revision.
4. **Stale POS-side doc.** `xorder-pos/docs/coordination/POS_TO_BACKEND.md` still says the backend
   `order_items` has no `menu_item_id` and POS-BE-006 is "APPROVED, not started." That is out of date:
   the migration exists (`2026_09_02_000100_add_menu_item_id_to_order_items_table.php`), the endpoint
   is live, and `BACKEND_TO_POS.md` marks POS-BE-006 **READY**. Trust the backend repo. When the
   §006 amendment (above) lands, sync the POS-side doc too.

---

## Rollout order (additive, deploy-safe)

1. Migration: add `order_items.name_ar` + `name_en` (nullable). Deploy — no behaviour change.
2. Backend: `PosPricingEngine` freezes both names; `PosOrderService` persists them (line rows +
   legacy JSON); public path writes the single name into all three (Minimum). Resources expose the
   two columns.
3. Frontend: add `itemName()` resolver; route board + receipt through it.
4. Amend BACKEND_TO_POS.md §006 (response gains `name_ar`/`name_en`; `name_snapshot` documented as
   fallback-only). No POS wire change required to ship the benefit.
5. (Follow-up, separate) menu SPA sends `menu_item_id` so QR orders become truly bilingual.

Each step is independently shippable and back-compatible; nothing rewrites live rows.

---

## Summary

- The order line stores one `name` string, so a POS order shows only the language captured at sale
  time — wrong when the dashboard is in the other locale. Menu items are bilingual; the line was not.
- Fix: add nullable `order_items.name_ar` + `name_en`; the backend resolves the line's already-sent
  `menu_item_id` and **freezes both names** from the item at creation (snapshot for history).
- Fallback when the id does not resolve: **accept** the line from the optional `name_snapshot`
  (money was taken), writing that one string into all three columns, `price_source: client_asserted`
  — never reject.
- Resources expose `name_ar`/`name_en` (plus legacy `name`); the dashboard resolves by locale with
  the app's existing `ar ? name_ar||name_en : name_en||name_ar` idiom, falling back to `name`.
- Back-compat is total: `name` is retained on every path, no live rows are rewritten, historical and
  public/QR rows fall through to `name`.
- POS catalog ids already ARE `menu_items.id` (bootstrap ships `id` + both names; the pricing engine
  already resolves by that id) — reliable on the cloud path; branch-server/islanded modes must
  preserve the cloud id as the wire id if ever built.

**File:** `/Users/amerelsayed/Projects/Xorder/xorder-new/docs/coordination/REVISION_ORDER_ITEM_ID.md`

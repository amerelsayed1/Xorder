<?php

namespace Tests\Feature;

use App\Enums\PurchaseStatus;
use App\Enums\SubscriptionStatus;
use App\Enums\TenantCapability;
use App\Exceptions\PurchasingRefusal;
use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\PurchaseOrder;
use App\Models\PurchaseOrderLine;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\StockItem;
use App\Models\StockLevel;
use App\Models\StockMovement;
use App\Models\Supplier;
use App\Models\Unit;
use App\Models\User;
use App\Services\PlanLimitService;
use App\Services\PurchaseOrderService;
use App\Services\ReceivingService;
use App\Services\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use LogicException;
use Tests\TestCase;

/**
 * CB-09 slice b: stock items, purchase orders, receiving at moving-average
 * cost, and the per-branch stock ledger.
 *
 * The default business here has `purchasing` and deliberately NOT `pos`
 * (owner decision 2026-09-12: purchasing is standalone), so every flow below
 * is proved for a café or cloud kitchen with no till.
 *
 * SQLite runs these, where lockForUpdate is a no-op. What is proved here is
 * the RULE under a stale read (a model loaded before another write, then
 * handed to the service), which is exactly what the lock-and-re-read in the
 * services defends against. The row lock itself is reviewed for PostgreSQL.
 */
class PurchasingOrdersAndStockTest extends TestCase
{
    use RefreshDatabase;

    private string $activityDir;

    protected function setUp(): void
    {
        parent::setUp();

        $this->activityDir = storage_path('framework/testing/audit-'.uniqid());
        config([
            'platform.activity_log_file' => true,
            'logging.channels.activity.path' => $this->activityDir.'/activity.log',
        ]);
        Log::forgetChannel('activity');
    }

    protected function tearDown(): void
    {
        Log::forgetChannel('activity');
        File::deleteDirectory($this->activityDir);

        parent::tearDown();
    }

    private function event(string $action, int $restaurantId): ?array
    {
        $file = $this->activityDir.'/activity-'.now()->format('Y-m-d').'.log';
        $events = file_exists($file)
            ? array_map(fn ($l) => json_decode($l, true), array_values(array_filter(explode("\n", file_get_contents($file)))))
            : [];

        return collect($events)->first(fn (array $e) => ($e['action'] ?? null) === $action && ($e['tenant_id'] ?? null) === $restaurantId);
    }

    // ------------------------------------------------------------- fixtures

    private function tenant(array $features = ['purchasing'], array $attributes = []): Restaurant
    {
        $restaurant = Restaurant::factory()->create($attributes);
        foreach ($features as $key) {
            $restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }

        return $restaurant;
    }

    private function owner(Restaurant $restaurant): User
    {
        return User::factory()->restaurantAdmin($restaurant->id)->create();
    }

    private function staffWith(Restaurant $restaurant, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($restaurant->id, $role->id)->create();
    }

    private function branch(Restaurant $restaurant, string $name = 'Downtown'): Branch
    {
        $branch = new Branch(['name_en' => $name]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        return $branch;
    }

    private function supplier(Restaurant $restaurant, array $attributes = []): Supplier
    {
        $supplier = new Supplier(array_merge(['name_en' => 'Cairo Poultry'], $attributes));
        $supplier->restaurant_id = $restaurant->id;
        $supplier->save();

        return $supplier;
    }

    private function unit(Restaurant $restaurant, string $code = 'tray30', bool $fraction = false): Unit
    {
        $unit = new Unit(['code' => $code, 'name_en' => 'Tray of 30', 'allows_fraction' => $fraction]);
        $unit->restaurant_id = $restaurant->id;
        $unit->save();

        return $unit;
    }

    private function stockItem(Restaurant $restaurant, array $attributes = []): StockItem
    {
        $item = new StockItem(array_merge(['name_en' => 'Chicken', 'unit_code' => 'kg'], $attributes));
        $item->restaurant_id = $restaurant->id;
        $item->save();

        return $item;
    }

    private function menuItem(Restaurant $restaurant, string $name): MenuItem
    {
        $category = Category::factory()->create(['restaurant_id' => $restaurant->id]);

        return MenuItem::factory()->create(['restaurant_id' => $restaurant->id, 'category_id' => $category->id, 'name_en' => $name]);
    }

    /** A business with purchasing and no pos: [restaurant, owner, branch, supplier, a kg stock item]. */
    private function scene(): array
    {
        $restaurant = $this->tenant();

        return [$restaurant, $this->owner($restaurant), $this->branch($restaurant), $this->supplier($restaurant), $this->stockItem($restaurant)];
    }

    private function line(StockItem $item, int $milli, int $cost, int $bp = 0): array
    {
        return ['stock_item_id' => $item->id, 'quantity_milli' => $milli, 'unit_cost_minor' => $cost, 'tax_rate_bp' => $bp];
    }

    private function freeLine(string $description, string $unit, int $milli, int $cost, int $bp = 0): array
    {
        return ['description' => $description, 'unit_code' => $unit, 'quantity_milli' => $milli, 'unit_cost_minor' => $cost, 'tax_rate_bp' => $bp];
    }

    private function draft(User $as, Branch $branch, Supplier $supplier, array $lines, array $extra = []): array
    {
        return $this->actingAs($as)->postJson('/api/dashboard/purchase-orders', array_merge([
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => $lines,
        ], $extra))->assertCreated()->json('data');
    }

    private function send(User $as, array $order): array
    {
        return $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$order['id']}/send")->assertOk()->json('data');
    }

    private function sentOrder(User $as, Branch $branch, Supplier $supplier, array $lines): array
    {
        return $this->send($as, $this->draft($as, $branch, $supplier, $lines));
    }

    /** @param array<int,int> $byIndex line position on the order => quantity_milli */
    private function receive(User $as, array $order, array $byIndex)
    {
        $lines = [];
        foreach ($byIndex as $i => $milli) {
            $lines[] = ['line_id' => $order['lines'][$i]['id'], 'quantity_milli' => $milli];
        }

        return $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$order['id']}/receipts", ['lines' => $lines]);
    }

    private function level(Branch $branch, StockItem $item): ?StockLevel
    {
        return StockLevel::withoutGlobalScopes()->where('branch_id', $branch->id)->where('stock_item_id', $item->id)->first();
    }

    // ----------------------------------------------------------- gate stack

    public function test_feature_off_blocks_every_slice_b_route_even_for_the_owner(): void
    {
        $restaurant = $this->tenant(['pos']);
        $owner = $this->owner($restaurant);

        foreach (['stock-items', 'purchase-orders', 'stock-levels', 'purchasing/lookups'] as $path) {
            $this->actingAs($owner)->getJson("/api/dashboard/{$path}")->assertForbidden();
        }
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'X', 'unit_code' => 'kg'])->assertForbidden();
        $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', ['lines' => []])->assertForbidden();
        $this->assertSame(0, StockItem::withoutGlobalScopes()->count());
    }

    public function test_staff_without_purchase_manage_is_refused_reads_and_writes(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $clerk = $this->staffWith($restaurant, ['menu.view', 'branches.view', 'settings.view', 'settings.update']);

        foreach (['stock-items', 'purchase-orders', 'stock-levels', 'purchasing/lookups', "purchase-orders/{$order['id']}"] as $path) {
            $this->actingAs($clerk)->getJson("/api/dashboard/{$path}")->assertForbidden();
        }
        $this->actingAs($clerk)->postJson('/api/dashboard/stock-items', ['name_en' => 'X', 'unit_code' => 'kg'])->assertForbidden();
        $this->actingAs($clerk)->postJson("/api/dashboard/purchase-orders/{$order['id']}/send")->assertForbidden();
        $this->actingAs($clerk)->postJson("/api/dashboard/purchase-orders/{$order['id']}/cancel")->assertForbidden();
        $this->assertSame('draft', PurchaseOrder::withoutGlobalScopes()->find($order['id'])->status->value);
    }

    public function test_a_buyer_with_only_purchase_manage_runs_the_whole_flow_on_a_business_with_no_pos(): void
    {
        $restaurant = $this->tenant(['purchasing']);
        $this->assertFalse($restaurant->hasFeature('pos'));
        $buyer = $this->staffWith($restaurant, ['purchase.manage']);
        $branch = $this->branch($restaurant);
        $supplier = $this->supplier($restaurant);
        $water = $this->menuItem($restaurant, 'Water 500ml');

        // The pickers work without branches.list or menu.view.
        $lookups = $this->actingAs($buyer)->getJson('/api/dashboard/purchasing/lookups')->assertOk();
        $lookups->assertJsonCount(1, 'data.branches')->assertJsonCount(7, 'data.units')
            ->assertJsonPath('data.menu_items.0.id', $water->id)->assertJsonPath('data.exponent', 2);
        $this->actingAs($buyer)->getJson('/api/dashboard/branches')->assertForbidden();

        $item = $this->actingAs($buyer)->postJson('/api/dashboard/stock-items', [
            'name_en' => 'Water 500ml', 'unit_code' => 'ea', 'menu_item_id' => $water->id,
        ])->assertCreated()->json('data');

        $order = $this->sentOrder($buyer, $branch, $supplier, [[
            'stock_item_id' => $item['id'], 'quantity_milli' => 24000, 'unit_cost_minor' => 500,
        ]]);
        $this->receive($buyer, $order, [0 => 24000])->assertOk()->assertJsonPath('data.status', 'received');

        $this->actingAs($buyer)->getJson('/api/dashboard/stock-levels')->assertOk()
            ->assertJsonPath('data.0.received_milli', 24000)
            ->assertJsonPath('data.0.average_cost_minor', 500)
            ->assertJsonPath('data.0.value_minor', 12000)
            ->assertJsonPath('meta.value_minor', 12000);
    }

    public function test_a_lapsed_subscription_blocks_writes_but_not_reads(): void
    {
        $restaurant = $this->tenant(['purchasing'], ['subscription_status' => SubscriptionStatus::EXPIRED]);
        $owner = $this->owner($restaurant);
        $branch = $this->branch($restaurant);
        $supplier = $this->supplier($restaurant);
        $item = $this->stockItem($restaurant);
        $this->actingAs($owner);
        $order = app(PurchaseOrderService::class)->create([
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id,
            'lines' => [$this->line($item, 1000, 100)],
        ], $owner);

        $this->actingAs($owner)->getJson('/api/dashboard/purchase-orders')->assertOk();
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$order->id}")->assertOk();
        $this->actingAs($owner)->getJson('/api/dashboard/stock-items')->assertOk();
        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk();

        foreach ([
            ['post', "/api/dashboard/purchase-orders/{$order->id}/send", []],
            ['post', "/api/dashboard/purchase-orders/{$order->id}/cancel", []],
            ['post', '/api/dashboard/stock-items', ['name_en' => 'X', 'unit_code' => 'kg']],
            ['put', "/api/dashboard/stock-items/{$item->id}", ['name_en' => 'Y', 'unit_code' => 'kg']],
        ] as [$verb, $url, $body]) {
            $this->actingAs($owner)->{$verb.'Json'}($url, $body)->assertForbidden()->assertJsonPath('code', 'subscription_inactive');
        }
        $this->assertSame('draft', $order->fresh()->status->value);
    }

    // ------------------------------------------------------ tenant isolation

    public function test_another_businesss_order_and_stock_item_are_404(): void
    {
        [, $owner] = $this->scene();
        [, $theirOwner, $theirBranch, $theirSupplier, $theirItem] = $this->scene();
        $order = $this->sentOrder($theirOwner, $theirBranch, $theirSupplier, [$this->line($theirItem, 1000, 100)]);

        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$order['id']}")->assertNotFound();
        $this->actingAs($owner)->putJson("/api/dashboard/purchase-orders/{$order['id']}", ['lines' => []])->assertNotFound();
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/send")->assertNotFound();
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/cancel")->assertNotFound();
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/receipts", [
            'lines' => [['line_id' => $order['lines'][0]['id'], 'quantity_milli' => 1000]],
        ])->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$theirItem->id}")->assertNotFound();
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$theirItem->id}", ['name_en' => 'Hijacked', 'unit_code' => 'kg'])->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$theirItem->id}/movements")->assertNotFound();

        $this->assertSame('sent', PurchaseOrder::withoutGlobalScopes()->find($order['id'])->status->value);
        $this->assertSame('Chicken', $theirItem->fresh()->name_en);

        // The lists only ever show your own rows.
        $this->actingAs($owner)->getJson('/api/dashboard/purchase-orders')->assertOk()->assertJsonCount(0, 'data');
        $this->actingAs($owner)->getJson('/api/dashboard/stock-items')->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_foreign_ids_in_the_body_are_422_and_restaurant_id_is_ignored(): void
    {
        [$mine, $owner, $branch, $supplier, $item] = $this->scene();
        [$theirs, , $theirBranch, $theirSupplier, $theirItem] = $this->scene();
        $this->unit($theirs, 'tray30');
        $theirMenuItem = $this->menuItem($theirs, 'Their water');
        $base = ['branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => [$this->line($item, 1000, 100)]];
        $post = fn (array $body) => $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', $body);

        $post(array_merge($base, ['branch_id' => $theirBranch->id]))->assertUnprocessable()->assertJsonValidationErrors('branch_id');
        $post(array_merge($base, ['supplier_id' => $theirSupplier->id]))->assertUnprocessable()->assertJsonValidationErrors('supplier_id');
        $post(array_merge($base, ['lines' => [$this->line($theirItem, 1000, 100)]]))
            ->assertUnprocessable()->assertJsonValidationErrors('lines.0.stock_item_id');
        $post(array_merge($base, ['lines' => [$this->freeLine('Eggs', 'tray30', 1000, 100)]]))
            ->assertUnprocessable()->assertJsonValidationErrors('lines.0.unit_code');
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'W', 'unit_code' => 'ea', 'menu_item_id' => $theirMenuItem->id])
            ->assertUnprocessable()->assertJsonValidationErrors('menu_item_id');

        $id = $post(array_merge($base, ['restaurant_id' => $theirs->id]))->assertCreated()->json('data.id');
        $this->assertSame($mine->id, PurchaseOrder::withoutGlobalScopes()->find($id)->restaurant_id);
        $this->assertSame($mine->id, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $id)->value('restaurant_id'));
        $this->assertSame(0, PurchaseOrder::withoutGlobalScopes()->where('restaurant_id', $theirs->id)->count());
    }

    public function test_receiving_a_line_of_another_order_is_refused_and_writes_nothing(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $a = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $b = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);

        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$a['id']}/receipts", [
            'lines' => [['line_id' => $b['lines'][0]['id'], 'quantity_milli' => 1000]],
        ])->assertUnprocessable()->assertJsonPath('code', 'LINE_NOT_ON_ORDER');

        $this->assertSame(0, PurchaseOrderLine::withoutGlobalScopes()->sum('received_milli'));
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
    }

    // ---------------------------------------------------------- stock items

    public function test_stock_items_take_a_unit_by_code_and_seed_the_defaults_first(): void
    {
        $restaurant = $this->tenant();
        $owner = $this->owner($restaurant);
        // This business never opened the Units page.
        $this->assertSame(0, Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());

        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_ar' => 'دقيق', 'unit_code' => ' KG '])
            ->assertCreated()->assertJsonPath('data.unit_code', 'kg')->assertJsonPath('data.is_active', true)
            ->assertJsonPath('data.holds_stock', false)->assertJsonPath('data.on_open_order', false);
        $this->assertSame(7, Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
        $this->assertSame($owner->id, $this->event('stock_item.created', $restaurant->id)['actor_id'] ?? null);

        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'X'])
            ->assertUnprocessable()->assertJsonValidationErrors('unit_code');
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'X', 'unit_code' => 'crate'])
            ->assertUnprocessable()->assertJsonValidationErrors('unit_code');
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['unit_code' => 'kg'])
            ->assertUnprocessable()->assertJsonValidationErrors('name_en');

        // A retired unit is refused for a new item.
        Unit::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->where('code', 'box')->update(['is_active' => false]);
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'Gloves', 'unit_code' => 'box'])
            ->assertUnprocessable()->assertJsonValidationErrors('unit_code');

        // A menu item is counted by one stock item at most.
        $water = $this->menuItem($restaurant, 'Water');
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'Water', 'unit_code' => 'ea', 'menu_item_id' => $water->id])
            ->assertCreated()->assertJsonPath('data.menu_item.id', $water->id);
        $this->actingAs($owner)->postJson('/api/dashboard/stock-items', ['name_en' => 'Water again', 'unit_code' => 'ea', 'menu_item_id' => $water->id])
            ->assertUnprocessable()->assertJsonValidationErrors('menu_item_id');

        // Stock items are not menu items: the menu quota never moves.
        $this->assertSame(1, MenuItem::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
        $this->assertSame(2, StockItem::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count());
        $this->assertNull(app(PlanLimitService::class)->itemLimitReached($restaurant));

        $id = StockItem::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->value('id');
        $this->actingAs($owner)->deleteJson("/api/dashboard/stock-items/{$id}")->assertStatus(405);
    }

    public function test_the_unit_is_locked_while_on_an_open_order_or_while_stock_is_held(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();

        // No history: the unit may change.
        $rice = $this->stockItem($restaurant, ['name_en' => 'Rice']);
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$rice->id}", ['name_en' => 'Rice', 'unit_code' => 'g'])
            ->assertOk()->assertJsonPath('data.unit_code', 'g');

        $order = $this->draft($owner, $branch, $supplier, [$this->line($item, 10000, 4000)]);
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$item->id}", ['name_en' => 'Chicken', 'unit_code' => 'g'])
            ->assertStatus(409)->assertJsonPath('code', 'STOCK_ITEM_ON_OPEN_ORDER');
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$item->id}")->assertJsonPath('data.on_open_order', true);

        $order = $this->send($owner, $order);
        $this->receive($owner, $order, [0 => 10000])->assertOk()->assertJsonPath('data.status', 'received');

        // The order is closed now, but the branch holds 10 kg.
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$item->id}", ['name_en' => 'Chicken', 'unit_code' => 'g'])
            ->assertStatus(409)->assertJsonPath('code', 'STOCK_ITEM_UNIT_LOCKED');
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$item->id}")
            ->assertJsonPath('data.holds_stock', true)->assertJsonPath('data.on_open_order', false);
        $this->assertSame('kg', $item->fresh()->unit_code);

        // Everything else about it may still change.
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$item->id}", ['name_en' => 'Chicken breast', 'unit_code' => 'kg', 'sku' => 'CH-01'])
            ->assertOk()->assertJsonPath('data.name_en', 'Chicken breast')->assertJsonPath('data.sku', 'CH-01');
    }

    // -------------------------------------------------------- purchase orders

    public function test_a_draft_snapshots_names_in_whichever_language_is_set_and_forces_the_item_unit(): void
    {
        [$restaurant, $owner, $branch, , $item] = $this->scene();
        $this->assertSame('ar', $restaurant->default_language->value);
        $arOnly = $this->supplier($restaurant, ['name_en' => null, 'name_ar' => 'دواجن القاهرة']);
        $enOnly = $this->supplier($restaurant, ['name_en' => 'Nile Dairy']);
        $both = $this->supplier($restaurant, ['name_en' => 'Delta Oils', 'name_ar' => 'زيوت الدلتا']);

        $this->assertSame('دواجن القاهرة', $this->draft($owner, $branch, $arOnly, [])['supplier_name']);
        $this->assertSame('Nile Dairy', $this->draft($owner, $branch, $enOnly, [])['supplier_name']);
        $this->assertSame('زيوت الدلتا', $this->draft($owner, $branch, $both, [])['supplier_name']);

        // The client says "box"; the stock item is counted in kg, so kg it is.
        // No description typed: the item's name (its only one, English) is the snapshot.
        $order = $this->draft($owner, $branch, $enOnly, [array_merge($this->line($item, 1500, 4000), ['unit_code' => 'box'])]);
        $this->assertSame('kg', $order['lines'][0]['unit_code']);
        $this->assertSame('Chicken', $order['lines'][0]['description']);

        // A rename before sending reaches the document; one after doesn't.
        $enOnly->update(['name_en' => 'Nile Dairy Co.']);
        $sent = $this->send($owner, $order);
        $this->assertSame('Nile Dairy Co.', $sent['supplier_name']);
        $enOnly->update(['name_en' => 'Renamed later']);
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$order['id']}")->assertJsonPath('data.supplier_name', 'Nile Dairy Co.');
    }

    public function test_send_numbers_gap_free_per_business_per_year_and_snapshots_totals_per_rate(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();
        $year = now()->setTimezone($restaurant->localTimezone())->format('Y');

        $first = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $second = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $discarded = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $this->assertNull($first['reference']);

        // A thrown-away draft consumes no number.
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$discarded['id']}/cancel")
            ->assertOk()->assertJsonPath('data.status', 'cancelled')->assertJsonPath('data.reference', null);

        // Numbered in the order they are SENT, not created.
        $this->assertSame("PO-{$year}-000001", $this->send($owner, $second)['reference']);
        $this->assertSame("PO-{$year}-000002", $this->send($owner, $first)['reference']);

        // Three lines of 33.33 at 14%: tax is rounded per rate (14.00), not per line (14.01).
        $taxed = $this->draft($owner, $branch, $supplier, [
            $this->line($item, 1000, 3333, 1400), $this->line($item, 1000, 3333, 1400), $this->line($item, 1000, 3333, 1400),
        ]);
        $this->assertSame(['subtotal_minor' => 9999, 'tax_minor' => 1400, 'total_minor' => 11399], $taxed['totals'], 'the live draft figure');
        $this->assertSame(0, PurchaseOrder::withoutGlobalScopes()->find($taxed['id'])->total_minor, 'nothing snapshotted before send');

        $sent = $this->send($owner, $taxed);
        $this->assertSame("PO-{$year}-000003", $sent['reference']);
        $this->assertNotNull($sent['ordered_at']);
        $row = PurchaseOrder::withoutGlobalScopes()->find($taxed['id']);
        $this->assertSame([9999, 1400, 11399], [$row->subtotal_minor, $row->tax_minor, $row->total_minor]);
        $this->assertSame(['EGP', 2], [$row->currency, $row->exponent]);

        // Another business has its own sequence.
        [, $theirOwner, $theirBranch, $theirSupplier, $theirItem] = $this->scene();
        $this->assertSame("PO-{$year}-000001", $this->sentOrder($theirOwner, $theirBranch, $theirSupplier, [$this->line($theirItem, 1000, 100)])['reference']);

        $sentEvent = $this->event('purchase_order.sent', $restaurant->id);
        $this->assertSame($owner->id, $sentEvent['actor_id'] ?? null);
        $this->assertSame($owner->id, $this->event('purchase_order.created', $restaurant->id)['actor_id'] ?? null);
        $this->assertNotNull($this->event('purchase_order.cancelled', $restaurant->id));
    }

    public function test_an_order_with_no_lines_cannot_be_sent_and_nothing_is_sent_twice(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();

        $empty = $this->draft($owner, $branch, $supplier, []);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$empty['id']}/send")
            ->assertUnprocessable()->assertJsonPath('code', 'PO_HAS_NO_LINES');
        $row = PurchaseOrder::withoutGlobalScopes()->find($empty['id']);
        $this->assertSame(PurchaseStatus::DRAFT, $row->status);
        $this->assertNull($row->reference);

        $sent = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$sent['id']}/send")
            ->assertStatus(409)->assertJsonPath('code', 'PO_NOT_DRAFT');
        $this->assertSame($sent['reference'], PurchaseOrder::withoutGlobalScopes()->find($sent['id'])->reference);
    }

    public function test_only_a_draft_is_editable_and_an_edit_replaces_the_lines_wholesale(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $draft = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100), $this->freeLine('Gas', 'ea', 1000, 9000)]);

        $this->actingAs($owner)->putJson("/api/dashboard/purchase-orders/{$draft['id']}", [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'notes' => 'Ring before delivering',
            'lines' => [$this->line($item, 2500, 4200)],
        ])->assertOk()->assertJsonCount(1, 'data.lines')->assertJsonPath('data.lines.0.ordered_milli', 2500)
            ->assertJsonPath('data.notes', 'Ring before delivering');
        $this->assertSame(1, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $draft['id'])->count());

        $this->send($owner, $draft);
        $this->actingAs($owner)->putJson("/api/dashboard/purchase-orders/{$draft['id']}", [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => [$this->line($item, 9000, 1)],
        ])->assertStatus(409)->assertJsonPath('code', 'PO_NOT_EDITABLE');
        $this->assertSame(2500, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $draft['id'])->value('ordered_milli'));
    }

    public function test_retired_suppliers_units_and_items_are_refused_on_new_orders_but_still_show_on_old_ones(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();
        $tray = $this->unit($restaurant, 'tray30');
        $old = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100), $this->freeLine('Eggs', 'tray30', 2000, 9000)]);
        $keptDraft = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);

        foreach ([$supplier, $tray, $item] as $row) {
            $row->forceFill(['is_active' => false])->save();
        }
        $other = $this->supplier($restaurant, ['name_en' => 'Nile Dairy']);
        $post = fn (array $body) => $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', array_merge(['branch_id' => $branch->id], $body));

        $post(['supplier_id' => $supplier->id, 'lines' => []])->assertUnprocessable()->assertJsonValidationErrors('supplier_id');
        $post(['supplier_id' => $other->id, 'lines' => [$this->freeLine('Eggs', 'tray30', 1000, 9000)]])
            ->assertUnprocessable()->assertJsonValidationErrors('lines.0.unit_code');
        $post(['supplier_id' => $other->id, 'lines' => [$this->line($item, 1000, 100)]])
            ->assertUnprocessable()->assertJsonValidationErrors('lines.0.stock_item_id');
        $this->assertSame(2, PurchaseOrder::withoutGlobalScopes()->count(), 'a refused save leaves nothing behind');

        // The old order still reads the same.
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$old['id']}")->assertOk()
            ->assertJsonPath('data.supplier_name', 'Cairo Poultry')
            ->assertJsonPath('data.supplier.is_active', false)
            ->assertJsonPath('data.lines.0.stock_item.is_active', false)
            ->assertJsonPath('data.lines.1.unit_code', 'tray30');
        $lookups = $this->actingAs($owner)->getJson('/api/dashboard/purchasing/lookups')->json('data');
        $this->assertFalse(collect($lookups['suppliers'])->firstWhere('id', $supplier->id)['is_active']);
        $this->assertFalse(collect($lookups['units'])->firstWhere('code', 'tray30')['is_active']);

        // Goods can still arrive against it.
        $this->receive($owner, $old, [0 => 1000, 1 => 2000])->assertOk()->assertJsonPath('data.status', 'received');

        // A draft that already named them can be re-saved, but not sent to a retired supplier.
        $this->actingAs($owner)->putJson("/api/dashboard/purchase-orders/{$keptDraft['id']}", [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => [$this->line($item, 2000, 100)],
        ])->assertOk();
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$keptDraft['id']}/send")
            ->assertUnprocessable()->assertJsonPath('code', 'PO_SUPPLIER_RETIRED');
    }

    public function test_a_fraction_is_refused_on_a_unit_counted_whole(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();

        $this->actingAs($owner)->postJson('/api/dashboard/purchase-orders', [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id, 'lines' => [$this->freeLine('Cans', 'ea', 1500, 100)],
        ])->assertUnprocessable()->assertJsonValidationErrors('lines.0.quantity_milli');

        // kg allows fractions.
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1500, 4000), $this->freeLine('Cans', 'ea', 2000, 100)]);
        $this->receive($owner, $order, [1 => 1500])->assertUnprocessable()->assertJsonPath('code', 'FRACTION_NOT_ALLOWED');
    }

    public function test_cancel_is_allowed_from_draft_or_sent_only(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $cancel = fn (array $o) => $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$o['id']}/cancel");

        $draft = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $cancel($draft)->assertOk()->assertJsonPath('data.status', 'cancelled');
        $cancel($draft)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CANCEL');

        $sent = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $cancel($sent)->assertOk()->assertJsonPath('data.status', 'cancelled');

        $partial = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 2000, 100)]);
        $this->receive($owner, $partial, [0 => 1000])->assertJsonPath('data.status', 'partially_received');
        $cancel($partial)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CANCEL');

        $full = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $this->receive($owner, $full, [0 => 1000])->assertJsonPath('data.status', 'received');
        $cancel($full)->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CANCEL');
    }

    /**
     * The till's gap (design §10 C2), by hand: a page loaded while the order
     * was "sent", a delivery booked in from somewhere else, then Cancel
     * pressed on the stale page. The service must re-read the status under
     * its lock and refuse, never trusting the model it was handed.
     */
    public function test_a_stale_cancel_after_a_receipt_is_refused(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 10000, 4000)]);

        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$order['id']}")->assertJsonPath('data.can_cancel', true);
        $stale = PurchaseOrder::withoutGlobalScopes()->findOrFail($order['id']);
        $this->assertSame(PurchaseStatus::SENT, $stale->status);

        // Meanwhile, half the delivery is booked in.
        $this->receive($owner, $order, [0 => 5000])->assertOk()->assertJsonPath('data.status', 'partially_received');
        $this->assertSame(PurchaseStatus::SENT, $stale->status, 'the stale model still says sent');

        try {
            app(PurchaseOrderService::class)->cancel($stale, $owner);
            $this->fail('A stale cancel must be refused.');
        } catch (PurchasingRefusal $e) {
            $this->assertSame('PO_CANNOT_CANCEL', $e->refusal);
            $this->assertSame(409, $e->status);
        }

        // And from the stale page, over HTTP.
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$order['id']}/cancel")
            ->assertStatus(409)->assertJsonPath('code', 'PO_CANNOT_CANCEL');

        $this->assertSame(PurchaseStatus::PARTIALLY_RECEIVED, $stale->fresh()->status);
        $this->assertSame(5000, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $order['id'])->value('received_milli'));
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(5000, $this->level($branch, $item)->quantity_milli);

        // The other way round: cancelled first, then a receipt from a stale page.
        $other = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 4000)]);
        $staleOther = PurchaseOrder::withoutGlobalScopes()->findOrFail($other['id']);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$other['id']}/cancel")->assertOk();
        try {
            app(ReceivingService::class)->receive($staleOther, [$other['lines'][0]['id'] => 1000], null, null, $owner);
            $this->fail('A receipt against a cancelled order must be refused.');
        } catch (PurchasingRefusal $e) {
            $this->assertSame('PO_NOT_OPEN', $e->refusal);
        }
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(5000, $this->level($branch, $item)->quantity_milli);
    }

    // ------------------------------------------------------------ receiving

    public function test_part_deliveries_book_in_at_the_tills_moving_average(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();

        // stock_costing_test.dart "a fractional delivery still lands on a whole
        // piastre": 7.5 kg at 44.00, then 12.5 kg at 47.30 → 20 kg at 46.06.
        // Here the second delivery comes in two parts (5 kg, then 7.5 kg).
        $first = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 7500, 4400)]);
        $this->receive($owner, $first, [0 => 7500])->assertOk()->assertJsonPath('data.status', 'received');
        $this->assertSame([7500, 4400], [$this->level($branch, $item)->quantity_milli, $this->level($branch, $item)->average_cost_minor]);

        $second = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 12500, 4730)]);
        $this->receive($owner, $second, [0 => 5000])->assertOk()
            ->assertJsonPath('data.status', 'partially_received')
            ->assertJsonPath('data.lines.0.outstanding_milli', 7500);
        // (33000 + 23650) × 1000 / 12500 = 4532 exactly.
        $this->assertSame([12500, 4532], [$this->level($branch, $item)->quantity_milli, $this->level($branch, $item)->average_cost_minor]);

        $this->receive($owner, $second, [0 => 7500])->assertOk()->assertJsonPath('data.status', 'received');
        // (56650 + 35475) × 1000 / 20000 = 4606.25 → 4606.
        $level = $this->level($branch, $item);
        $this->assertSame([20000, 4606, 'kg'], [$level->quantity_milli, $level->average_cost_minor, $level->unit_code]);

        // Each movement carries the position it produced; the last equals the level.
        $moves = StockMovement::withoutGlobalScopes()->orderBy('id')->get();
        $this->assertSame([7500, 5000, 7500], $moves->pluck('quantity_milli')->all());
        $this->assertSame([4400, 4730, 4730], $moves->pluck('unit_cost_minor')->all(), 'costed at the order line price');
        $this->assertSame([7500, 12500, 20000], $moves->pluck('balance_milli')->all());
        $this->assertSame([4400, 4532, 4606], $moves->pluck('average_cost_minor')->all());
        $this->assertSame(['receipt'], $moves->pluck('kind')->unique()->values()->all());

        $replay = app(StockLedger::class)->replay($branch->id, $item->id);
        $this->assertSame([], $replay['drift']);
        $this->assertTrue($replay['level_matches']);
        $this->assertSame([20000, 4606], [$replay['milli'], $replay['cost']]);

        // The till's vector in one go, at a second branch, through the whole stack.
        $maadi = $this->branch($restaurant, 'Maadi');
        $a = $this->sentOrder($owner, $maadi, $supplier, [$this->line($item, 7500, 4400)]);
        $this->receive($owner, $a, [0 => 7500])->assertOk();
        $b = $this->sentOrder($owner, $maadi, $supplier, [$this->line($item, 12500, 4730)]);
        $this->receive($owner, $b, [0 => 12500])->assertOk();
        $this->assertSame([20000, 4606], [$this->level($maadi, $item)->quantity_milli, $this->level($maadi, $item)->average_cost_minor]);

        $this->assertNotNull($this->event('purchase_order.received', $restaurant->id));
    }

    public function test_over_delivery_is_accepted_and_closes_the_line(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 10000, 4000)]);

        $this->receive($owner, $order, [0 => 12000])->assertOk()
            ->assertJsonPath('data.status', 'received')
            ->assertJsonPath('data.lines.0.received_milli', 12000)
            ->assertJsonPath('data.lines.0.outstanding_milli', 0);
        $this->assertSame(12000, $this->level($branch, $item)->quantity_milli);
    }

    public function test_the_status_follows_the_lines(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();
        $oil = $this->stockItem($restaurant, ['name_en' => 'Oil', 'unit_code' => 'l']);
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100), $this->line($oil, 2000, 300)]);

        $this->receive($owner, $order, [0 => 1000])->assertJsonPath('data.status', 'partially_received');
        $this->receive($owner, $order, [1 => 1500])->assertJsonPath('data.status', 'partially_received');
        $this->receive($owner, $order, [1 => 500])->assertJsonPath('data.status', 'received');
    }

    public function test_a_line_with_no_stock_item_moves_the_order_and_touches_no_ledger(): void
    {
        [, $owner, $branch, $supplier] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->freeLine('Gas cylinder', 'ea', 2000, 15000)]);

        $this->receive($owner, $order, [0 => 2000])->assertOk()->assertJsonPath('data.status', 'received')
            ->assertJsonPath('data.received_value_minor', 30000);
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(0, StockLevel::withoutGlobalScopes()->count());
    }

    public function test_a_receipt_is_all_or_nothing(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 10000, 4000), $this->freeLine('Cans', 'ea', 2000, 100)]);

        // The first line is fine; the second breaks a rule. Nothing may stick.
        $this->receive($owner, $order, [0 => 10000, 1 => 1500])->assertUnprocessable()->assertJsonPath('code', 'FRACTION_NOT_ALLOWED');

        $this->assertSame(0, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $order['id'])->sum('received_milli'));
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(0, (int) StockLevel::withoutGlobalScopes()->sum('quantity_milli'));
        $this->assertSame(PurchaseStatus::SENT, PurchaseOrder::withoutGlobalScopes()->find($order['id'])->status);
    }

    public function test_receiving_never_converts_units(): void
    {
        [$restaurant, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 4000)]);

        // Stock held in boxes that the platform's own rules could never have
        // produced (say, imported), then a delivery in kg.
        (new StockLevel)->forceFill([
            'restaurant_id' => $restaurant->id, 'branch_id' => $branch->id, 'stock_item_id' => $item->id,
            'quantity_milli' => 5000, 'unit_code' => 'box', 'average_cost_minor' => 100,
        ])->save();

        $this->receive($owner, $order, [0 => 1000])->assertStatus(409)->assertJsonPath('code', 'STOCK_HELD_IN_ANOTHER_UNIT');
        $this->assertSame([5000, 'box'], [$this->level($branch, $item)->quantity_milli, $this->level($branch, $item)->unit_code]);
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(0, PurchaseOrderLine::withoutGlobalScopes()->where('purchase_order_id', $order['id'])->value('received_milli'));

        // And a line whose unit no longer matches its item (changed behind
        // the service's back): refused too, never booked in the wrong unit.
        StockLevel::withoutGlobalScopes()->where('stock_item_id', $item->id)->delete();
        StockItem::withoutGlobalScopes()->whereKey($item->id)->update(['unit_code' => 'g']);
        $this->receive($owner, $order, [0 => 1000])->assertStatus(409)->assertJsonPath('code', 'LINE_UNIT_DIFFERS');
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
    }

    public function test_receiving_needs_an_open_order_and_a_quantity(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();

        $draft = $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $this->receive($owner, $draft, [0 => 1000])->assertStatus(409)->assertJsonPath('code', 'PO_NOT_OPEN');

        $sent = $this->send($owner, $draft);
        $this->receive($owner, $sent, [0 => 0])->assertUnprocessable()->assertJsonPath('code', 'NOTHING_RECEIVED');
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$sent['id']}/receipts", ['lines' => []])
            ->assertUnprocessable()->assertJsonValidationErrors('lines');

        $this->receive($owner, $sent, [0 => 1000])->assertOk();
        $this->receive($owner, $sent, [0 => 1000])->assertStatus(409)->assertJsonPath('code', 'PO_NOT_OPEN');
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
    }

    public function test_movements_are_append_only(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $order = $this->sentOrder($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);
        $this->receive($owner, $order, [0 => 1000])->assertOk();
        $movement = StockMovement::withoutGlobalScopes()->firstOrFail();

        try {
            $movement->forceFill(['quantity_milli' => 999999])->save();
            $this->fail('A movement must not be updated.');
        } catch (LogicException) {
        }
        try {
            $movement->delete();
            $this->fail('A movement must not be deleted.');
        } catch (LogicException) {
        }

        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame(1000, StockMovement::withoutGlobalScopes()->value('quantity_milli'));
    }

    // ---------------------------------------------------- levels and ledger

    public function test_levels_are_per_branch_and_the_ledger_reads_newest_first(): void
    {
        [$restaurant, $owner, $downtown, $supplier, $item] = $this->scene();
        $maadi = $this->branch($restaurant, 'Maadi');

        $a = $this->sentOrder($owner, $downtown, $supplier, [$this->line($item, 10000, 4000)]);
        $this->receive($owner, $a, [0 => 10000])->assertOk();
        $b = $this->sentOrder($owner, $maadi, $supplier, [$this->line($item, 4000, 5000)]);
        $this->receive($owner, $b, [0 => 4000])->assertOk();

        // Stock at Maadi is not stock Downtown has: two positions, two averages.
        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk()
            ->assertJsonCount(2, 'data')->assertJsonPath('meta.value_minor', 40000 + 20000);
        $this->actingAs($owner)->getJson("/api/dashboard/stock-levels?branch_id={$maadi->id}")->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.received_milli', 4000)
            ->assertJsonPath('data.0.average_cost_minor', 5000)
            ->assertJsonPath('data.0.value_minor', 20000)
            ->assertJsonPath('data.0.unit_code', 'kg');

        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$item->id}/movements")->assertOk()
            ->assertJsonPath('total', 2)
            ->assertJsonPath('data.0.branch_id', $maadi->id)
            ->assertJsonPath('data.0.kind', 'receipt')
            ->assertJsonPath('data.0.purchase_order_reference', $b['reference']);
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$item->id}/movements?branch_id={$downtown->id}")->assertOk()
            ->assertJsonPath('total', 1)->assertJsonPath('data.0.balance_milli', 10000);
    }

    public function test_a_branch_with_purchasing_history_cannot_be_deleted(): void
    {
        [, $owner, $branch, $supplier, $item] = $this->scene();
        $this->draft($owner, $branch, $supplier, [$this->line($item, 1000, 100)]);

        $this->actingAs($owner)->deleteJson("/api/dashboard/branches/{$branch->id}")->assertStatus(409);
        $this->assertNotNull(Branch::withoutGlobalScopes()->find($branch->id));
    }
}

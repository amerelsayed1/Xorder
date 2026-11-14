<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Enums\TenantCapability;
use App\Models\Branch;
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
use App\Services\StockLedger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

/**
 * CB-09 slice d: opening stock, waste, adjustments and counts, each one new
 * movement in the append-only ledger, costed with the till's arithmetic.
 *
 * The default business has `purchasing` and NOT `pos` (purchasing is
 * standalone, owner 2026-09-12), so every flow is proved for a client with
 * no till.
 *
 * SQLite runs these, where lockForUpdate is a no-op. What is proved is the
 * RULE: the count's difference and the cost of an issue are read from the
 * position at the time of writing, not from what a page saw. The row lock
 * itself was checked by hand on PostgreSQL (design §16).
 */
class StockAdjustmentsTest extends TestCase
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

    private function supplier(Restaurant $restaurant): Supplier
    {
        $supplier = new Supplier(['name_en' => 'Cairo Poultry']);
        $supplier->restaurant_id = $restaurant->id;
        $supplier->save();

        return $supplier;
    }

    private function stockItem(Restaurant $restaurant, array $attributes = []): StockItem
    {
        $item = new StockItem(array_merge(['name_en' => 'Chicken', 'unit_code' => 'kg'], $attributes));
        $item->restaurant_id = $restaurant->id;
        $item->save();

        return $item;
    }

    /** A business with purchasing and no pos: [restaurant, owner, branch, a kg stock item]. */
    private function scene(): array
    {
        $restaurant = $this->tenant();

        return [$restaurant, $this->owner($restaurant), $this->branch($restaurant), $this->stockItem($restaurant)];
    }

    private function adjust(User $as, Branch $branch, StockItem $item, string $kind, array $extra = []): TestResponse
    {
        return $this->actingAs($as)->postJson('/api/dashboard/stock-adjustments', array_merge([
            'branch_id' => $branch->id, 'stock_item_id' => $item->id, 'kind' => $kind,
        ], $extra));
    }

    private function opening(User $as, Branch $branch, StockItem $item, int $milli, int $cost): TestResponse
    {
        return $this->adjust($as, $branch, $item, 'opening', ['quantity_milli' => $milli, 'unit_cost_minor' => $cost]);
    }

    /** A sent order for one line of $item, received in full or in part: returns the order JSON. */
    private function receivedOrder(User $as, Branch $branch, Supplier $supplier, StockItem $item, int $ordered, int $cost, int $received): array
    {
        $order = $this->actingAs($as)->postJson('/api/dashboard/purchase-orders', [
            'branch_id' => $branch->id, 'supplier_id' => $supplier->id,
            'lines' => [['stock_item_id' => $item->id, 'quantity_milli' => $ordered, 'unit_cost_minor' => $cost]],
        ])->assertCreated()->json('data');
        $order = $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$order['id']}/send")->assertOk()->json('data');
        if ($received > 0) {
            $order = $this->actingAs($as)->postJson("/api/dashboard/purchase-orders/{$order['id']}/receipts", [
                'lines' => [['line_id' => $order['lines'][0]['id'], 'quantity_milli' => $received]],
            ])->assertOk()->json('data');
        }

        return $order;
    }

    /** [quantity_milli, average_cost_minor] */
    private function position(Branch $branch, StockItem $item): ?array
    {
        $level = StockLevel::withoutGlobalScopes()->where('branch_id', $branch->id)->where('stock_item_id', $item->id)->first();

        return $level ? [$level->quantity_milli, $level->average_cost_minor] : null;
    }

    private function assertReplaysClean(Branch $branch, StockItem $item): void
    {
        $replay = app(StockLedger::class)->replay($branch->id, $item->id);
        $this->assertSame([], $replay['drift'], 'every movement records the position the fold gives');
        $this->assertTrue($replay['level_matches'], 'the level equals the end of the fold');
    }

    // ----------------------------------------------------------- gate stack

    public function test_feature_off_blocks_stock_adjustments_even_for_the_owner(): void
    {
        $restaurant = $this->tenant(['pos']);
        $owner = $this->owner($restaurant);

        $this->opening($owner, $this->branch($restaurant), $this->stockItem($restaurant), 1000, 100)->assertForbidden();
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
    }

    public function test_purchase_manage_alone_is_enough_on_a_business_with_no_pos_and_nothing_less_is(): void
    {
        [$restaurant, , $branch, $item] = $this->scene();
        $this->assertFalse($restaurant->hasFeature('pos'));

        $clerk = $this->staffWith($restaurant, ['menu.view', 'branches.view', 'settings.view', 'settings.update']);
        $this->opening($clerk, $branch, $item, 1000, 100)->assertForbidden();
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());

        $buyer = $this->staffWith($restaurant, ['purchase.manage']);
        $this->opening($buyer, $branch, $item, 1000, 100)->assertCreated()
            ->assertJsonPath('data.created_by', $buyer->name);
        $this->assertSame($buyer->id, StockMovement::withoutGlobalScopes()->value('created_by'));
    }

    public function test_a_lapsed_subscription_blocks_adjustments_but_not_reading_stock(): void
    {
        $restaurant = $this->tenant(['purchasing'], ['subscription_status' => SubscriptionStatus::EXPIRED]);
        $owner = $this->owner($restaurant);

        $this->opening($owner, $this->branch($restaurant), $this->stockItem($restaurant), 1000, 100)
            ->assertForbidden()->assertJsonPath('code', 'subscription_inactive');
        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk();
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->count());
    }

    // ------------------------------------------------------ tenant isolation

    public function test_another_businesss_branch_or_item_is_422_their_ledger_404_and_restaurant_id_is_ignored(): void
    {
        [$mine, $owner, $branch, $item] = $this->scene();
        [$theirs, $theirOwner, $theirBranch, $theirItem] = $this->scene();
        $this->opening($theirOwner, $theirBranch, $theirItem, 1000, 100)->assertCreated();

        $this->opening($owner, $theirBranch, $item, 1000, 100)->assertUnprocessable()->assertJsonValidationErrors('branch_id');
        $this->opening($owner, $branch, $theirItem, 1000, 100)->assertUnprocessable()->assertJsonValidationErrors('stock_item_id');
        $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$theirItem->id}/movements")->assertNotFound();

        $this->adjust($owner, $branch, $item, 'opening', ['quantity_milli' => 1000, 'unit_cost_minor' => 100, 'restaurant_id' => $theirs->id])
            ->assertCreated();
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->where('restaurant_id', $mine->id)->count());
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->where('restaurant_id', $theirs->id)->count());
        $this->assertSame([1000, 100], $this->position($theirBranch, $theirItem), 'their stock is untouched');
    }

    // --------------------------------------------------------------- opening

    public function test_opening_stock_enters_at_its_cost_like_a_receipt_once_per_branch(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();

        // stock_costing_test.dart "nothing on hand takes the arriving price".
        $this->opening($owner, $branch, $item, 10000, 4730)->assertCreated()
            ->assertJsonPath('data.kind', 'opening')
            ->assertJsonPath('data.reason', 'opening_balance')
            ->assertJsonPath('data.quantity_milli', 10000)
            ->assertJsonPath('data.unit_code', 'kg')
            ->assertJsonPath('data.balance_milli', 10000)
            ->assertJsonPath('data.average_cost_minor', 4730)
            ->assertJsonPath('data.purchase_order_id', null)
            ->assertJsonPath('data.level.quantity_milli', 10000)
            ->assertJsonPath('data.level.value_minor', 47300);

        // One opening per branch and item; a correction is an adjustment.
        $this->opening($owner, $branch, $item, 1000, 100)->assertStatus(409)->assertJsonPath('code', 'OPENING_ALREADY_RECORDED');
        // Per branch: another branch has its own opening.
        $maadi = $this->branch($restaurant, 'Maadi');
        $this->opening($owner, $maadi, $item, 2000, 5000)->assertCreated();

        // The cost is required, and a quantity above zero.
        $oil = $this->stockItem($restaurant, ['name_en' => 'Oil', 'unit_code' => 'l']);
        $this->adjust($owner, $branch, $oil, 'opening', ['quantity_milli' => 1000])
            ->assertUnprocessable()->assertJsonValidationErrors('unit_cost_minor');
        $this->opening($owner, $branch, $oil, 0, 100)->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');
        $this->opening($owner, $branch, $oil, -1000, 100)->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');

        // After a delivery it averages like a second one: "the textbook case",
        // 10 kg received at 40.00 then 10 kg of opening stock at 50.00 → 45.00.
        $this->receivedOrder($owner, $branch, $this->supplier($restaurant), $oil, 10000, 4000, 10000);
        $this->opening($owner, $branch, $oil, 10000, 5000)->assertCreated();
        $this->assertSame([20000, 4500], $this->position($branch, $oil));

        $event = $this->event('stock_movement.opening', $restaurant->id);
        $this->assertSame('opening_balance', $event['properties']['reason']);
        $this->assertSame(47300, $event['properties']['value_minor']);
        $this->assertReplaysClean($branch, $oil);
    }

    // ----------------------------------------------------------------- waste

    public function test_waste_leaves_at_the_average_and_never_moves_it(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();
        $this->opening($owner, $branch, $item, 10000, 4500)->assertCreated();

        // stock_costing_test.dart "does not move the cost"; COGS 135.00.
        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 3000, 'reason' => 'spoiled', 'unit_code' => 'kg'])
            ->assertCreated()
            ->assertJsonPath('data.kind', 'waste')
            ->assertJsonPath('data.reason', 'spoiled')
            ->assertJsonPath('data.quantity_milli', -3000)
            ->assertJsonPath('data.unit_cost_minor', 4500)
            ->assertJsonPath('data.balance_milli', 7000)
            ->assertJsonPath('data.average_cost_minor', 4500);

        $event = $this->event('stock_movement.waste', $restaurant->id);
        $this->assertSame(13500, $event['properties']['value_minor'], 'the till\'s costOfGoods: 3 kg at 45.00');
        $this->assertSame(['milli' => 10000, 'average_cost_minor' => 4500], $event['properties']['before']);

        // The rules of the entry.
        $waste = fn (array $body) => $this->adjust($owner, $branch, $item, 'waste', $body);
        $waste(['quantity_milli' => 1000])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $waste(['quantity_milli' => 1000, 'reason' => 'found'])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $waste(['quantity_milli' => 1000, 'reason' => 'other'])->assertUnprocessable()->assertJsonValidationErrors('note');
        $waste(['quantity_milli' => 1000, 'reason' => 'damaged', 'unit_cost_minor' => 1])->assertUnprocessable()->assertJsonValidationErrors('unit_cost_minor');
        $waste(['quantity_milli' => 0, 'reason' => 'damaged'])->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');
        $waste(['quantity_milli' => -1000, 'reason' => 'damaged'])->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');
        $waste(['quantity_milli' => 1000, 'reason' => 'other', 'note' => 'Dropped a tray'])->assertCreated()
            ->assertJsonPath('data.note', 'Dropped a tray');

        $this->assertSame([6000, 4500], $this->position($branch, $item));
        $this->assertReplaysClean($branch, $item);
    }

    public function test_stock_may_go_below_zero_and_the_next_arrival_is_not_averaged_against_the_debt(): void
    {
        [, $owner, $branch, $item] = $this->scene();
        $this->opening($owner, $branch, $item, 1000, 4500)->assertCreated();

        // "is allowed to go negative": 3 kg written off of 1 kg recorded.
        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 3000, 'reason' => 'expired'])->assertCreated()
            ->assertJsonPath('data.balance_milli', -2000)
            ->assertJsonPath('data.average_cost_minor', 4500)
            ->assertJsonPath('data.level.value_minor', -9000);
        // "negative stock is worth a negative — it is not hidden".
        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk()
            ->assertJsonPath('data.0.quantity_milli', -2000)
            ->assertJsonPath('data.0.value_minor', -9000)
            ->assertJsonPath('meta.value_minor', -9000);

        // "negative on hand takes it too, and the debt settles".
        $this->adjust($owner, $branch, $item, 'adjustment', ['quantity_milli' => 10000, 'unit_cost_minor' => 4730, 'reason' => 'found'])
            ->assertCreated();
        $this->assertSame([8000, 4730], $this->position($branch, $item));
        $this->assertReplaysClean($branch, $item);
    }

    // ----------------------------------------------------------- adjustments

    public function test_adjustments_go_either_way_and_a_rise_with_no_cost_enters_at_the_average(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();
        $this->opening($owner, $branch, $item, 10000, 4000)->assertCreated();
        $adjust = fn (array $body) => $this->adjust($owner, $branch, $item, 'adjustment', $body);

        $adjust(['quantity_milli' => 2000, 'reason' => 'found'])->assertCreated()
            ->assertJsonPath('data.unit_cost_minor', 4000)->assertJsonPath('data.balance_milli', 12000)->assertJsonPath('data.average_cost_minor', 4000);
        $adjust(['quantity_milli' => -500, 'reason' => 'missing'])->assertCreated()
            ->assertJsonPath('data.kind', 'adjustment')->assertJsonPath('data.quantity_milli', -500)->assertJsonPath('data.unit_cost_minor', 4000);
        // 1 kg at 52.00 into 11.5 kg at 40.00 → 40.96.
        $adjust(['quantity_milli' => 1000, 'unit_cost_minor' => 5200, 'reason' => 'entry_error'])->assertCreated()
            ->assertJsonPath('data.balance_milli', 12500)->assertJsonPath('data.average_cost_minor', 4096);

        $before = StockMovement::withoutGlobalScopes()->count();
        $adjust(['quantity_milli' => 0, 'reason' => 'entry_error'])->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');
        $adjust(['quantity_milli' => -1000, 'reason' => 'found'])->assertUnprocessable()->assertJsonPath('code', 'REASON_NEEDS_INCREASE');
        $adjust(['quantity_milli' => 1000, 'reason' => 'missing'])->assertUnprocessable()->assertJsonPath('code', 'REASON_NEEDS_DECREASE');
        $adjust(['quantity_milli' => 1000, 'reason' => 'internal_use'])->assertUnprocessable()->assertJsonPath('code', 'REASON_NEEDS_DECREASE');
        $adjust(['quantity_milli' => -1000, 'unit_cost_minor' => 100, 'reason' => 'entry_error'])->assertUnprocessable()->assertJsonValidationErrors('unit_cost_minor');
        $adjust(['quantity_milli' => 1000, 'reason' => 'spoiled'])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $adjust(['quantity_milli' => 1000, 'reason' => 'stock_count'])->assertUnprocessable()->assertJsonValidationErrors('reason');
        $this->assertSame($before, StockMovement::withoutGlobalScopes()->count());

        // With no history at this branch there is no average to fall back
        // on: a cost is required, and nothing is written (not even a level).
        $maadi = $this->branch($restaurant, 'Maadi');
        $this->adjust($owner, $maadi, $item, 'adjustment', ['quantity_milli' => 1000, 'reason' => 'found'])
            ->assertUnprocessable()->assertJsonPath('code', 'UNIT_COST_REQUIRED');
        $this->assertNull($this->position($maadi, $item));

        $this->assertSame([12500, 4096], $this->position($branch, $item));
        $this->assertReplaysClean($branch, $item);
    }

    // ----------------------------------------------------------------- count

    public function test_a_count_posts_the_difference_from_the_position_at_the_time_of_writing(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();
        $this->opening($owner, $branch, $item, 10000, 4000)->assertCreated();
        $count = fn (int $counted, array $extra = []) => $this->adjust($owner, $branch, $item, 'count', array_merge(['counted_milli' => $counted], $extra));

        $count(8500)->assertCreated()
            ->assertJsonPath('data.kind', 'adjustment')
            ->assertJsonPath('data.reason', 'stock_count')
            ->assertJsonPath('data.quantity_milli', -1500)
            ->assertJsonPath('data.unit_cost_minor', 4000)
            ->assertJsonPath('data.balance_milli', 8500);
        $count(8500)->assertUnprocessable()->assertJsonPath('code', 'COUNT_MATCHES');

        // A page that saw 8.5 kg; 2 kg is received meanwhile; the count of
        // 9 kg is posted against 10.5 kg, not against the page's 8.5 kg.
        $this->receivedOrder($owner, $branch, $this->supplier($restaurant), $item, 2000, 4000, 2000);
        $this->assertSame([10500, 4000], $this->position($branch, $item));
        $count(9000)->assertCreated()->assertJsonPath('data.quantity_milli', -1500)->assertJsonPath('data.balance_milli', 9000);

        // A count above the record enters at the average (or a typed cost).
        $count(9500)->assertCreated()->assertJsonPath('data.quantity_milli', 500)->assertJsonPath('data.average_cost_minor', 4000);

        $count(-1)->assertUnprocessable()->assertJsonValidationErrors('counted_milli');
        $this->adjust($owner, $branch, $item, 'count', ['counted_milli' => 1000, 'quantity_milli' => 1000])
            ->assertUnprocessable()->assertJsonValidationErrors('quantity_milli');
        $this->adjust($owner, $branch, $item, 'count', ['counted_milli' => 1000, 'reason' => 'found'])
            ->assertUnprocessable()->assertJsonValidationErrors('reason');

        $event = $this->event('stock_movement.count', $restaurant->id);
        $this->assertSame(8500, $event['properties']['counted_milli']);
        $this->assertSame(-1500, $event['properties']['quantity_milli']);
        $this->assertSame('stock_count', $event['properties']['reason']);
        $this->assertReplaysClean($branch, $item);
    }

    public function test_a_whole_unit_refuses_fractions(): void
    {
        [$restaurant, $owner, $branch] = $this->scene();
        $unit = new Unit(['code' => 'tray30', 'name_en' => 'Tray of 30', 'allows_fraction' => false]);
        $unit->restaurant_id = $restaurant->id;
        $unit->save();
        $eggs = $this->stockItem($restaurant, ['name_en' => 'Eggs', 'unit_code' => 'tray30']);

        $this->opening($owner, $branch, $eggs, 1500, 9000)->assertUnprocessable()->assertJsonPath('code', 'FRACTION_NOT_ALLOWED');
        $this->opening($owner, $branch, $eggs, 2000, 9000)->assertCreated();
        $this->adjust($owner, $branch, $eggs, 'count', ['counted_milli' => 1500])->assertUnprocessable()->assertJsonPath('code', 'FRACTION_NOT_ALLOWED');
        $this->adjust($owner, $branch, $eggs, 'waste', ['quantity_milli' => 500, 'reason' => 'damaged'])->assertUnprocessable()->assertJsonPath('code', 'FRACTION_NOT_ALLOWED');
        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
    }

    // ---------------------------------------------------- parity end to end

    public function test_a_mixed_history_values_to_the_tills_figures_and_replays_clean(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();

        // Opening 7.5 kg at 44.00, then 12.5 kg received at 47.30: the
        // till's "fractional delivery" vector, 20 kg at 46.06.
        $this->opening($owner, $branch, $item, 7500, 4400)->assertCreated();
        $this->receivedOrder($owner, $branch, $this->supplier($restaurant), $item, 12500, 4730, 12500);
        $this->assertSame([20000, 4606], $this->position($branch, $item));

        // Waste 3 kg: the average holds, value 170.00 kg-worth = 783.02.
        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 3000, 'reason' => 'spoiled'])->assertCreated();
        $this->assertSame([17000, 4606], $this->position($branch, $item));
        // A count finds 16 kg: 1 kg out at the average.
        $this->adjust($owner, $branch, $item, 'count', ['counted_milli' => 16000])->assertCreated();

        $this->actingAs($owner)->getJson('/api/dashboard/stock-levels')->assertOk()
            ->assertJsonPath('data.0.quantity_milli', 16000)
            ->assertJsonPath('data.0.received_milli', 16000)
            ->assertJsonPath('data.0.average_cost_minor', 4606)
            ->assertJsonPath('data.0.value_minor', 73696)
            ->assertJsonPath('meta.value_minor', 73696);

        // The ledger, newest first, with each kind's reason.
        $moves = $this->actingAs($owner)->getJson("/api/dashboard/stock-items/{$item->id}/movements")->assertOk()->json('data');
        $this->assertSame(['adjustment', 'waste', 'receipt', 'opening'], array_column($moves, 'kind'));
        $this->assertSame(['stock_count', 'spoiled', null, 'opening_balance'], array_column($moves, 'reason'));
        $this->assertSame([-1000, -3000, 12500, 7500], array_column($moves, 'quantity_milli'));
        $this->assertSame([16000, 17000, 20000, 7500], array_column($moves, 'balance_milli'));
        $this->assertSame([4606, 4606, 4606, 4400], array_column($moves, 'average_cost_minor'));

        $replay = app(StockLedger::class)->replay($branch->id, $item->id);
        $this->assertSame([16000, 4606, 4, []], [$replay['milli'], $replay['cost'], $replay['movements'], $replay['drift']]);
        $this->assertTrue($replay['level_matches']);
    }

    // ------------------------------------------------------------------ units

    public function test_a_movement_never_converts_units(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();
        $this->opening($owner, $branch, $item, 1000, 100)->assertCreated();

        // The page showed grams; the item is counted in kg.
        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 500, 'reason' => 'damaged', 'unit_code' => 'g'])
            ->assertStatus(409)->assertJsonPath('code', 'ADJUSTMENT_UNIT_DIFFERS');

        // The unit can't change while stock is held (slice b's lock, unchanged).
        $this->actingAs($owner)->putJson("/api/dashboard/stock-items/{$item->id}", ['name_en' => 'Chicken', 'unit_code' => 'g'])
            ->assertStatus(409)->assertJsonPath('code', 'STOCK_ITEM_UNIT_LOCKED');

        // A branch holding the item in another unit (imported, say): refused, never converted.
        StockLevel::withoutGlobalScopes()->where('stock_item_id', $item->id)->update(['unit_code' => 'box']);
        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 500, 'reason' => 'damaged'])
            ->assertStatus(409)->assertJsonPath('code', 'STOCK_HELD_IN_ANOTHER_UNIT');
        $this->adjust($owner, $branch, $item, 'count', ['counted_milli' => 0])
            ->assertStatus(409)->assertJsonPath('code', 'STOCK_HELD_IN_ANOTHER_UNIT');

        $this->assertSame(1, StockMovement::withoutGlobalScopes()->count());
        $this->assertSame([1000, 'box'], [
            StockLevel::withoutGlobalScopes()->where('stock_item_id', $item->id)->value('quantity_milli'),
            StockLevel::withoutGlobalScopes()->where('stock_item_id', $item->id)->value('unit_code'),
        ]);
    }

    // ----------------------------------------------------------------- orders

    public function test_adjustments_never_touch_a_purchase_order_even_a_closed_short_one(): void
    {
        [$restaurant, $owner, $branch, $item] = $this->scene();
        $supplier = $this->supplier($restaurant);

        $short = $this->receivedOrder($owner, $branch, $supplier, $item, 10000, 4000, 6000);
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$short['id']}/close", ['reason' => 'supplier_cannot_supply'])
            ->assertOk()->assertJsonPath('data.status', 'received')->assertJsonPath('data.closed_short', true);
        $open = $this->receivedOrder($owner, $branch, $supplier, $item, 5000, 4000, 0);

        $snapshot = fn () => [
            PurchaseOrder::withoutGlobalScopes()->orderBy('id')->get()->map(fn ($o) => $o->only([
                'id', 'status', 'closed_short_at', 'close_reason', 'subtotal_minor', 'total_minor', 'updated_at',
            ]))->all(),
            PurchaseOrderLine::withoutGlobalScopes()->orderBy('id')->get(['id', 'ordered_milli', 'received_milli', 'updated_at'])->toArray(),
        ];
        $before = $snapshot();

        $this->adjust($owner, $branch, $item, 'waste', ['quantity_milli' => 1000, 'reason' => 'spoiled'])->assertCreated();
        $this->adjust($owner, $branch, $item, 'adjustment', ['quantity_milli' => 500, 'reason' => 'found'])->assertCreated();
        $this->adjust($owner, $branch, $item, 'opening', ['quantity_milli' => 1000, 'unit_cost_minor' => 4000])->assertCreated();
        $this->adjust($owner, $branch, $item, 'count', ['counted_milli' => 2000])->assertCreated();

        $this->assertEquals($before, $snapshot(), 'no order, line or status changed');
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->where('kind', '!=', 'receipt')->whereNotNull('purchase_order_id')->count());
        $this->assertSame(0, StockMovement::withoutGlobalScopes()->where('kind', '!=', 'receipt')->whereNotNull('purchase_order_line_id')->count());

        // The closed order stays closed, the open one stays open.
        $this->actingAs($owner)->postJson("/api/dashboard/purchase-orders/{$short['id']}/receipts", [
            'lines' => [['line_id' => $short['lines'][0]['id'], 'quantity_milli' => 1000]],
        ])->assertStatus(409)->assertJsonPath('code', 'PO_NOT_OPEN');
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$short['id']}")->assertOk()
            ->assertJsonPath('data.lines.0.received_milli', 6000)
            ->assertJsonPath('data.lines.0.not_coming_milli', 4000);
        $this->actingAs($owner)->getJson("/api/dashboard/purchase-orders/{$open['id']}")->assertOk()
            ->assertJsonPath('data.status', 'sent');

        $this->assertSame([2000, 4000], $this->position($branch, $item));
        $this->assertReplaysClean($branch, $item);
    }
}

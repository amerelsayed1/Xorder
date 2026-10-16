<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * S2-1 (16 Oct 2026): the order queue is where a till's sales land, so a
 * restaurant that bought the POS — and not online ordering — must be able to
 * read it. The gate is `feature:system_ordering|pos`; a plan with neither is
 * still refused, and the refusal is a 403 the page can name.
 */
class PosOrdersOnDashboardTest extends PosTestCase
{
    private function ringUpASale(): int
    {
        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00,
            'discounted_price' => null,
        ]);
        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();

        $token = $this->claimTerminal()['token'];

        return $this->postJson('/api/pos/orders', [
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-10-16T08:00:00+02:00',
            'lines' => [['menu_item_id' => $burger->id, 'quantity' => 2, 'name_snapshot' => 'Classic Burger']],
            'payments' => [['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $cash->id, 'amount_minor' => 20000]],
        ], $this->deviceHeaders($token))->assertCreated()->json('data.id');
    }

    public function test_a_pos_only_restaurant_sees_its_till_sales_on_the_orders_page(): void
    {
        // PosTestCase grants `pos` and nothing else — no system_ordering.
        $this->assertFalse($this->restaurant->fresh()->hasFeature('system_ordering'));

        $orderId = $this->ringUpASale();

        $list = $this->actingAs($this->owner)->getJson('/api/dashboard/orders')
            ->assertOk()
            ->json();

        $this->assertSame([$orderId], array_column($list['data'], 'id'));
        $this->assertSame('pos', $list['data'][0]['source']);
        $this->assertSame(1, $list['summary']['counts']['all']);

        // The till says `takeaway`; the board's Pickup tab must still find it.
        $this->actingAs($this->owner)->getJson('/api/dashboard/orders?order_type=pickup')
            ->assertOk()
            ->assertJsonPath('data.0.id', $orderId);
        $this->actingAs($this->owner)->getJson('/api/dashboard/orders?order_type=delivery')
            ->assertOk()
            ->assertJsonCount(0, 'data');

        $this->actingAs($this->owner)->getJson('/api/dashboard/orders/new-count')->assertOk();
    }

    public function test_a_restaurant_with_neither_feature_is_refused_the_order_queue(): void
    {
        $bare = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($bare->id)->create();

        $this->actingAs($owner)->getJson('/api/dashboard/orders')->assertForbidden();
        $this->actingAs($owner)->getJson('/api/dashboard/orders/new-count')->assertForbidden();
    }

    public function test_the_single_feature_form_of_the_gate_still_admits_online_ordering_alone(): void
    {
        $online = Restaurant::factory()->create();
        $online->features()->create(['feature_key' => 'system_ordering', 'is_enabled' => true]);
        $owner = User::factory()->restaurantAdmin($online->id)->create();

        $this->actingAs($owner)->getJson('/api/dashboard/orders')->assertOk();
    }
}

<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Order;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class OrderTableAssociationTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private DiningTable $table;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'cafe', 'ordering_enabled' => true,
        ]);
        $branch = new Branch(['name_en' => 'Main']);
        $branch->restaurant_id = $this->restaurant->id;
        $branch->save();
        $area = new DiningArea(['branch_id' => $branch->id, 'name_en' => 'Indoor']);
        $area->restaurant_id = $this->restaurant->id;
        $area->save();
        $this->table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => '12',
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $this->table->restaurant_id = $this->restaurant->id;
        $this->table->branch_id = $branch->id;
        $this->table->save();
    }

    private function makeSession(): MenuSession
    {
        $s = new MenuSession([
            'branch_id' => $this->table->branch_id,
            'dining_area_id' => $this->table->dining_area_id,
            'table_id' => $this->table->id,
            'language' => 'en',
            'session_token' => Str::random(40),
            'started_at' => now(), 'last_activity_at' => now(), 'expires_at' => now()->addHours(4),
        ]);
        $s->restaurant_id = $this->restaurant->id;
        $s->save();

        return $s;
    }

    private function orderPayload(array $extra = []): array
    {
        return array_merge([
            'items' => [['name' => 'Latte', 'qty' => 1, 'line_total' => 50]],
            'total' => 50,
        ], $extra);
    }

    public function test_order_with_session_token_is_bound_to_the_table(): void
    {
        $session = $this->makeSession();

        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
            'order_type' => 'pickup', // should be overridden to dine_in
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertSame($this->table->id, $order->table_id);
        $this->assertSame($this->table->dining_area_id, $order->dining_area_id);
        $this->assertSame($this->table->branch_id, $order->branch_id);
        $this->assertSame($session->id, $order->menu_session_id);
        $this->assertSame('dine_in', $order->order_type);
    }

    public function test_order_without_session_is_unbound(): void
    {
        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'order_type' => 'delivery',
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertNull($order->table_id);
        $this->assertSame('delivery', $order->order_type);
    }

    public function test_stale_session_token_still_records_the_order_untagged(): void
    {
        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => Str::random(40), // never issued
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertNull($order->table_id);
    }
}

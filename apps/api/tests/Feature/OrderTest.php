<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderTest extends TestCase
{
    use RefreshDatabase;

    private function payload(): array
    {
        return [
            'items' => [
                ['name' => 'برجر', 'qty' => 2, 'options' => ['جبنة إضافية'], 'line_total' => 150],
                ['name' => 'Pizza', 'qty' => 1, 'options' => [], 'line_total' => 80],
            ],
            'total' => 230,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
        ];
    }

    public function test_guest_can_record_an_order(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'demo', 'ordering_enabled' => true]);

        $res = $this->postJson('/api/public/restaurants/demo/orders', $this->payload());

        $res->assertCreated()->assertJsonPath('data.code', 'ORD-'.$res->json('data.id'));
        $this->assertDatabaseHas('orders', [
            'restaurant_id' => $r->id,
            'status' => 'NEW',
            'customer_name' => 'Amer',
            'source' => 'whatsapp',
        ]);
    }

    public function test_order_requires_items(): void
    {
        Restaurant::factory()->create(['slug' => 'demo', 'ordering_enabled' => true]);

        $this->postJson('/api/public/restaurants/demo/orders', ['items' => [], 'total' => 0])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['items']);
    }

    public function test_hidden_restaurant_rejects_orders(): void
    {
        Restaurant::factory()->suspended()->create(['slug' => 'closed', 'ordering_enabled' => true]);

        $this->postJson('/api/public/restaurants/closed/orders', $this->payload())
            ->assertNotFound();
    }

    public function test_ordering_disabled_rejects_orders(): void
    {
        Restaurant::factory()->create(['slug' => 'view-only', 'ordering_enabled' => false]);

        $this->postJson('/api/public/restaurants/view-only/orders', $this->payload())
            ->assertStatus(422);
    }

    public function test_admin_sees_only_own_orders(): void
    {
        $mine = Restaurant::factory()->create(['ordering_enabled' => true]);
        $other = Restaurant::factory()->create(['ordering_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($mine->id)->create();

        $this->postJson("/api/public/restaurants/{$mine->slug}/orders", $this->payload())->assertCreated();
        $this->postJson("/api/public/restaurants/{$other->slug}/orders", $this->payload())->assertCreated();

        $this->actingAs($admin)->getJson('/api/dashboard/orders')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->actingAs($admin)->getJson('/api/dashboard/orders/new-count')
            ->assertOk()
            ->assertJsonPath('data.new_orders', 1);
    }

    public function test_admin_can_update_order_status_but_not_foreign_orders(): void
    {
        $mine = Restaurant::factory()->create(['ordering_enabled' => true]);
        $other = Restaurant::factory()->create(['ordering_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($mine->id)->create();

        $this->postJson("/api/public/restaurants/{$mine->slug}/orders", $this->payload());
        $this->postJson("/api/public/restaurants/{$other->slug}/orders", $this->payload());

        $myOrder = Order::withoutGlobalScopes()->where('restaurant_id', $mine->id)->first();
        $foreignOrder = Order::withoutGlobalScopes()->where('restaurant_id', $other->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$myOrder->id}/status", ['status' => 'CONFIRMED'])
            ->assertOk()
            ->assertJsonPath('data.status', 'CONFIRMED');

        // Cross-tenant access is a 404, never a 403 (information hiding).
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$foreignOrder->id}/status", ['status' => 'CONFIRMED'])
            ->assertNotFound();
    }

    public function test_order_status_rejects_unknown_value(): void
    {
        $r = Restaurant::factory()->create(['ordering_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'BOGUS'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['status']);
    }

    public function test_orders_filter_by_status(): void
    {
        $r = Restaurant::factory()->create(['ordering_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());

        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED']);

        $this->actingAs($admin)->getJson('/api/dashboard/orders?status=NEW')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }
}

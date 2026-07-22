<?php

namespace Tests\Feature;

use App\Enums\OrderingMode;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderingModeTest extends TestCase
{
    use RefreshDatabase;

    private function payload(): array
    {
        return [
            'items' => [['name' => 'X', 'qty' => 1, 'options' => [], 'line_total' => 50]],
            'total' => 50,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
        ];
    }

    private function withMenu(Restaurant $r): Restaurant
    {
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        return $r;
    }

    public function test_restaurants_default_to_both_mode(): void
    {
        $r = Restaurant::factory()->create();

        $this->assertSame(OrderingMode::BOTH, $r->fresh()->ordering_mode);
    }

    public function test_public_menu_exposes_ordering_mode(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'wa-only', 'ordering_mode' => OrderingMode::WHATSAPP]));

        $this->getJson('/api/public/restaurants/wa-only/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_mode', 'whatsapp');
    }

    public function test_whatsapp_only_mode_rejects_a_system_order(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'wa', 'ordering_mode' => OrderingMode::WHATSAPP]));

        $this->postJson('/api/public/restaurants/wa/orders', $this->payload())->assertStatus(422);
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_system_mode_records_order_tagged_system(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'sys', 'ordering_mode' => OrderingMode::SYSTEM]));

        $this->postJson('/api/public/restaurants/sys/orders', $this->payload())->assertCreated();
        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'source' => 'system']);
    }

    public function test_both_mode_records_order_tagged_whatsapp(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'both', 'ordering_mode' => OrderingMode::BOTH]));

        $this->postJson('/api/public/restaurants/both/orders', $this->payload())->assertCreated();
        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'source' => 'whatsapp']);
    }

    public function test_restaurant_admin_can_change_ordering_mode_via_profile(): void
    {
        $r = Restaurant::factory()->create(['ordering_mode' => OrderingMode::BOTH]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', ['ordering_mode' => 'system'])
            ->assertOk()
            ->assertJsonPath('data.ordering_mode', 'system');

        $this->assertSame(OrderingMode::SYSTEM, $r->fresh()->ordering_mode);
    }
}

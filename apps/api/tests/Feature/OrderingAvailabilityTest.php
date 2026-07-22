<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Whether the public menu takes orders is decided entirely by the plan
 * entitlements (whatsapp_ordering / system_ordering → effectiveOrderingMode).
 * There is no separate per-restaurant ordering switch: a plan with no ordering
 * channel yields a display-only menu.
 */
class OrderingAvailabilityTest extends TestCase
{
    use RefreshDatabase;

    private function withMenu(Restaurant $r): Restaurant
    {
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        return $r;
    }

    public function test_public_menu_flags_ordering_enabled_when_the_plan_grants_a_channel(): void
    {
        $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'orders-open']));

        $this->getJson('/api/public/restaurants/orders-open/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_enabled', true);
    }

    public function test_public_menu_flags_ordering_disabled_when_the_plan_grants_no_channel(): void
    {
        // No ordering features → display-only menu.
        $this->withMenu(Restaurant::factory()->create(['slug' => 'view-only']));

        $this->getJson('/api/public/restaurants/view-only/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_enabled', false)
            ->assertJsonPath('data.restaurant.ordering_mode', null);
    }

    public function test_order_placement_is_rejected_when_the_plan_grants_no_channel(): void
    {
        $this->withMenu(Restaurant::factory()->create(['slug' => 'view-only']));

        $this->postJson('/api/public/restaurants/view-only/orders', [
            'items' => [['name' => 'Item', 'qty' => 1, 'line_total' => 10]],
            'total' => 10,
        ])->assertStatus(422);
    }

    public function test_ordering_availability_is_per_restaurant(): void
    {
        $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'open']));
        $this->withMenu(Restaurant::factory()->create(['slug' => 'closed']));

        $this->getJson('/api/public/restaurants/open/menu')
            ->assertOk()->assertJsonPath('data.restaurant.ordering_enabled', true);

        $this->getJson('/api/public/restaurants/closed/menu')
            ->assertOk()->assertJsonPath('data.restaurant.ordering_enabled', false);
    }
}

<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Two independent gates decide whether the public menu takes orders:
 *
 *  1. the plan entitlements (whatsapp_ordering / system_ordering →
 *     effectiveOrderingMode), owned by the Super Admin; and
 *  2. `accepts_orders`, the owner's own "are we taking orders right now"
 *     switch in their dashboard.
 *
 * Both must say yes. Crucially the second cannot override the first — pausing
 * is not a way to buy ordering, and un-pausing is not a way to get it free.
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

    // ------------------------------------------- the owner's own pause switch

    public function test_owner_can_pause_ordering_on_an_entitled_plan(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'paused']));
        $r->forceFill(['accepts_orders' => false])->save();

        $this->getJson('/api/public/restaurants/paused/menu')
            ->assertOk()
            // Indistinguishable from a display-only menu, by design: the
            // diner is not told which of the two reasons applies.
            ->assertJsonPath('data.restaurant.ordering_enabled', false);
    }

    public function test_a_paused_restaurant_rejects_order_placement(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'paused-post']));
        $r->forceFill(['accepts_orders' => false])->save();

        // Enforced server-side: a stale menu tab must not post into a closed
        // kitchen just because its UI was rendered before the pause.
        $this->postJson('/api/public/restaurants/paused-post/orders', [
            'items' => [['name' => 'Item', 'qty' => 1, 'line_total' => 10]],
            'total' => 10,
        ])
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.ordering_disabled'));
    }

    public function test_un_pausing_restores_ordering(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'resumed']));
        $r->forceFill(['accepts_orders' => false])->save();

        $this->getJson('/api/public/restaurants/resumed/menu')
            ->assertJsonPath('data.restaurant.ordering_enabled', false);

        $r->forceFill(['accepts_orders' => true])->save();

        $this->getJson('/api/public/restaurants/resumed/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_enabled', true);
    }

    /** The switch cannot conjure an entitlement the plan does not include. */
    public function test_accepting_orders_does_not_grant_ordering_without_a_plan_channel(): void
    {
        $r = $this->withMenu(Restaurant::factory()->create(['slug' => 'no-plan-channel']));
        $r->forceFill(['accepts_orders' => true])->save();

        $this->getJson('/api/public/restaurants/no-plan-channel/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_enabled', false);
    }

    public function test_restaurants_default_to_accepting_orders(): void
    {
        $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'fresh']));

        $this->getJson('/api/public/restaurants/fresh/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_enabled', true);
    }
}

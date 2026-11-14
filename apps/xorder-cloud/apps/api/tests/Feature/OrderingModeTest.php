<?php

namespace Tests\Feature;

use App\Enums\OrderingMode;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\BuildsDinerOrders;
use Tests\TestCase;

class OrderingModeTest extends TestCase
{
    use BuildsDinerOrders;
    use RefreshDatabase;

    private function payload(): array
    {
        return [
            'items' => $this->dinerItems([['name' => 'X', 'qty' => 1, 'options' => [], 'line_total' => 50]]),
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

    public function test_restaurants_default_to_whatsapp_mode(): void
    {
        $r = Restaurant::factory()->create();

        $this->assertSame(OrderingMode::WHATSAPP, $r->fresh()->ordering_mode);
    }

    public function test_public_menu_exposes_ordering_mode(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'wa-only', 'ordering_mode' => OrderingMode::WHATSAPP]));

        $this->getJson('/api/public/restaurants/wa-only/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.ordering_mode', 'whatsapp');
    }

    public function test_whatsapp_mode_records_the_order_as_pending(): void
    {
        // live-board-to-pos D6: a WhatsApp checkout is recorded (it used to be
        // refused), but PENDING until an employee accepts it.
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'wa', 'ordering_mode' => OrderingMode::WHATSAPP]));

        $this->postJson('/api/public/restaurants/wa/orders', $this->payload())->assertCreated();
        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'source' => 'whatsapp', 'status' => 'PENDING']);
    }

    public function test_system_mode_records_order_tagged_system(): void
    {
        $r = $this->withMenu(Restaurant::factory()->withOrdering()->create(['slug' => 'sys', 'ordering_mode' => OrderingMode::SYSTEM]));

        $this->postJson('/api/public/restaurants/sys/orders', $this->payload())->assertCreated();
        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'source' => 'system']);
    }

    public function test_restaurant_admin_cannot_change_ordering_mode_via_profile(): void
    {
        // The ordering channel is set on the plan/Super-Admin side, not by the
        // restaurant owner. A stray ordering_mode in the profile PUT is ignored.
        $r = Restaurant::factory()->create(['ordering_mode' => OrderingMode::WHATSAPP]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'name_en' => 'Renamed', 'ordering_mode' => 'system',
        ])->assertOk();

        $this->assertSame(OrderingMode::WHATSAPP, $r->fresh()->ordering_mode);
    }

    /**
     * The owner controls the switch, not the channel. These are the two halves
     * of the same boundary: they may pause what the plan gave them, and may not
     * change what the plan gave them.
     */
    public function test_restaurant_admin_can_pause_and_resume_ordering_via_profile(): void
    {
        $r = Restaurant::factory()->withOrdering()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', ['accepts_orders' => false])
            ->assertOk()
            ->assertJsonPath('data.accepts_orders', false);

        $this->assertFalse($r->fresh()->accepts_orders);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', ['accepts_orders' => true])
            ->assertOk()
            ->assertJsonPath('data.accepts_orders', true);

        $this->assertTrue($r->fresh()->accepts_orders);
    }

    /** The dashboard needs to know whether the switch would control anything. */
    public function test_profile_reports_whether_the_plan_entitles_ordering(): void
    {
        $entitled = Restaurant::factory()->withOrdering()->create();
        $this->actingAs(User::factory()->restaurantAdmin($entitled->id)->create())
            ->getJson('/api/dashboard/restaurant')
            ->assertOk()
            ->assertJsonPath('data.ordering_entitled', true);

        $plain = Restaurant::factory()->create();
        $this->actingAs(User::factory()->restaurantAdmin($plain->id)->create())
            ->getJson('/api/dashboard/restaurant')
            ->assertOk()
            ->assertJsonPath('data.ordering_entitled', false);
    }
}

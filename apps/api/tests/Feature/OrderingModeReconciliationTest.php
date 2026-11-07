<?php

namespace Tests\Feature;

use Tests\Concerns\BuildsDinerOrders;
use App\Enums\Feature;
use App\Enums\OrderingMode;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * ordering_mode is the restaurant's channel preference; the plan entitlements
 * (whatsapp_ordering / system_ordering features) are the ceiling. They are
 * reconciled at config time: RestaurantFeatureService::apply coerces
 * ordering_mode down to what the plan grants, so the stored mode is always a
 * value the plan permits and the order pipeline can trust it.
 */
class OrderingModeReconciliationTest extends TestCase
{
    use BuildsDinerOrders;

    use RefreshDatabase;

    /** Enable exactly the given feature keys on the restaurant. */
    private function grant(Restaurant $r, array $on): void
    {
        $map = [];
        foreach (Feature::cases() as $f) {
            $map[$f->value] = in_array($f->value, $on, true);
        }
        app(RestaurantFeatureService::class)->apply($r, $map);
    }

    public function test_available_modes_reflect_entitlements(): void
    {
        $wa = Restaurant::factory()->create();
        $this->grant($wa, ['whatsapp_ordering']);
        $this->assertSame([OrderingMode::WHATSAPP], $wa->fresh()->availableOrderingModes());

        $sys = Restaurant::factory()->create();
        $this->grant($sys, ['system_ordering']);
        $this->assertSame([OrderingMode::SYSTEM], $sys->fresh()->availableOrderingModes());

        $both = Restaurant::factory()->create();
        $this->grant($both, ['whatsapp_ordering', 'system_ordering']);
        $this->assertSame(
            [OrderingMode::WHATSAPP, OrderingMode::SYSTEM],
            $both->fresh()->availableOrderingModes(),
        );
    }

    public function test_applying_features_coerces_ordering_mode(): void
    {
        // Prefers system but the plan only grants WhatsApp → coerced to whatsapp.
        $r = Restaurant::factory()->create(['ordering_mode' => OrderingMode::SYSTEM]);
        $this->grant($r, ['whatsapp_ordering']);
        $this->assertSame(OrderingMode::WHATSAPP, $r->fresh()->ordering_mode);

        // Plan grants both channels → a system preference is preserved (both are
        // available, so the stored choice stands).
        $r2 = Restaurant::factory()->create(['ordering_mode' => OrderingMode::SYSTEM]);
        $this->grant($r2, ['whatsapp_ordering', 'system_ordering']);
        $this->assertSame(OrderingMode::SYSTEM, $r2->fresh()->ordering_mode);

        // Downgrade: a system-only preference under a WhatsApp-only plan → whatsapp.
        $r3 = Restaurant::factory()->create(['ordering_mode' => OrderingMode::SYSTEM]);
        $this->grant($r3, ['whatsapp_ordering']);
        $this->assertSame(OrderingMode::WHATSAPP, $r3->fresh()->ordering_mode);
    }

    public function test_order_pipeline_honours_the_coerced_mode(): void
    {
        // WhatsApp-only plan → mode coerced to whatsapp → no order record created.
        $wa = Restaurant::factory()->create(['slug' => 'nosys', 'ordering_mode' => OrderingMode::SYSTEM]);
        $this->grant($wa, ['whatsapp_ordering']);
        $cat = Category::factory()->for($wa)->create(['is_active' => true]);
        MenuItem::factory()->for($wa)->for($cat)->create();

        $this->getJson('/api/public/restaurants/nosys/menu')
            ->assertOk()->assertJsonPath('data.restaurant.ordering_mode', 'whatsapp');

        $this->postJson('/api/public/restaurants/nosys/orders', [
            'items' => $this->dinerItems([['name' => 'Item', 'qty' => 1, 'line_total' => 10]]),
            'total' => 10,
        ])->assertStatus(422);

        // Plan grants system ordering → mode records the order, tagged system.
        $sys = Restaurant::factory()->create(['slug' => 'hassys', 'ordering_mode' => OrderingMode::SYSTEM]);
        $this->grant($sys, ['system_ordering']);
        $cat2 = Category::factory()->for($sys)->create(['is_active' => true]);
        MenuItem::factory()->for($sys)->for($cat2)->create();

        $this->postJson('/api/public/restaurants/hassys/orders', [
            'items' => $this->dinerItems([['name' => 'Item', 'qty' => 1, 'line_total' => 10]]),
            'total' => 10,
        ])->assertCreated();
        $this->assertDatabaseHas('orders', ['restaurant_id' => $sys->id, 'source' => 'system']);
    }
}

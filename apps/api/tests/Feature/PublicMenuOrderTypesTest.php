<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PublicMenuOrderTypesTest extends TestCase
{
    use RefreshDatabase;

    private function menuOrderTypes(string $slug): array
    {
        return $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->json('data.restaurant.order_types');
    }

    public function test_disabled_order_type_is_not_offered(): void
    {
        $r = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'pk-only']);
        $r->features()->createMany([
            ['feature_key' => 'pickup', 'is_enabled' => true],
            ['feature_key' => 'delivery', 'is_enabled' => false],
        ]);

        $this->assertSame(['pickup'], $this->menuOrderTypes('pk-only'));
    }

    public function test_legacy_restaurant_without_feature_rows_keeps_both(): void
    {
        Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'legacy']);

        $this->assertSame(['pickup', 'delivery'], $this->menuOrderTypes('legacy'));
    }

    public function test_both_disabled_yields_no_order_types(): void
    {
        $r = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE, 'slug' => 'dine-only']);
        $r->features()->createMany([
            ['feature_key' => 'pickup', 'is_enabled' => false],
            ['feature_key' => 'delivery', 'is_enabled' => false],
        ]);

        $this->assertSame([], $this->menuOrderTypes('dine-only'));
    }
}

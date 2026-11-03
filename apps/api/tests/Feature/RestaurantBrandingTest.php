<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Public branding for the tenant login screen ({slug}.host/admin/login).
 *
 * Unauthenticated and addressable by slug, so the whole question is what it
 * hands out: enough to brand a login page, and nothing else about the business.
 */
class RestaurantBrandingTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_returns_the_branding_for_a_slug(): void
    {
        Restaurant::factory()->create([
            'slug' => 'bistro', 'name_en' => 'Bistro', 'status' => RestaurantStatus::ACTIVE,
            'brand_color' => '#112233',
        ]);

        $this->getJson('/api/public/restaurants/bistro/branding')
            ->assertOk()
            ->assertJsonPath('data.slug', 'bistro')
            ->assertJsonPath('data.name_en', 'Bistro')
            ->assertJsonPath('data.brand_color', '#112233');
    }

    public function test_it_exposes_only_branding_fields(): void
    {
        // The admin of a suspended or unpaid restaurant still needs to reach a
        // branded login, so this endpoint answers for tenants the public menu
        // would refuse. That makes the field list the entire security boundary.
        $restaurant = Restaurant::factory()->create([
            'slug' => 'bistro', 'status' => RestaurantStatus::ACTIVE,
        ]);

        $data = $this->getJson('/api/public/restaurants/bistro/branding')->assertOk()->json('data');

        $this->assertSame(
            ['name_en', 'name_ar', 'slug', 'logo_url', 'brand_color', 'secondary_color'],
            array_keys($data),
        );
        foreach (['id', 'email', 'phone', 'whatsapp_number', 'subscription_status', 'plan_id'] as $private) {
            $this->assertArrayNotHasKey($private, $data, "$private must not be public");
        }
        $this->assertNotContains($restaurant->id, $data, 'the internal id must not leak');
    }

    public function test_a_suspended_restaurant_still_serves_branding_so_its_admin_can_log_in(): void
    {
        Restaurant::factory()->create(['slug' => 'paused', 'status' => RestaurantStatus::SUSPENDED]);

        $this->getJson('/api/public/restaurants/paused/branding')->assertOk();
    }

    public function test_an_unknown_slug_is_a_404(): void
    {
        $this->getJson('/api/public/restaurants/nope/branding')->assertNotFound();
    }
}

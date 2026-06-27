<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class PublicMenuTest extends TestCase
{
    use RefreshDatabase;

    public function test_active_restaurant_menu_is_available(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'open']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/open/menu')
            ->assertOk()
            ->assertJsonPath('available', true)
            ->assertJsonCount(1, 'data.categories');
    }

    public function test_suspended_restaurant_menu_is_unavailable(): void
    {
        $r = Restaurant::factory()->suspended()->create(['slug' => 'closed']);

        $this->getJson('/api/public/restaurants/closed/menu')
            ->assertOk()
            ->assertJsonPath('available', false);

        // Web page shows the unavailable message with HTTP 200 (not 404).
        $this->get('/r/closed?lang=en')->assertOk()->assertSee('currently unavailable', false);
    }

    public function test_inactive_and_empty_categories_are_hidden(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'hide']);
        // inactive category with an item -> hidden
        $inactive = Category::factory()->for($r)->create(['is_active' => false]);
        MenuItem::factory()->for($r)->for($inactive)->create();
        // active but empty category -> hidden
        Category::factory()->for($r)->create(['is_active' => true, 'name_en' => 'Empty']);
        // active with item -> shown
        $shown = Category::factory()->for($r)->create(['is_active' => true, 'name_en' => 'Shown']);
        MenuItem::factory()->for($r)->for($shown)->create();

        $this->getJson('/api/public/restaurants/hide/menu')
            ->assertOk()
            ->assertJsonCount(1, 'data.categories')
            ->assertJsonPath('data.categories.0.name_en', 'Shown');
    }

    public function test_unavailable_items_are_still_listed(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'badge']);
        $cat = Category::factory()->for($r)->create();
        MenuItem::factory()->for($r)->for($cat)->unavailable()->create();

        $this->getJson('/api/public/restaurants/badge/menu')
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.is_available', false);
    }

    public function test_unknown_slug_returns_404(): void
    {
        $this->getJson('/api/public/restaurants/nope/menu')->assertNotFound();
    }

    public function test_public_payload_excludes_internal_fields(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'priv']);
        $cat = Category::factory()->for($r)->create();
        MenuItem::factory()->for($r)->for($cat)->create();

        $res = $this->getJson('/api/public/restaurants/priv/menu')->assertOk();
        $restaurant = $res->json('data.restaurant');

        $this->assertArrayNotHasKey('subscription_status', $restaurant);
        $this->assertArrayNotHasKey('status', $restaurant);
    }
}

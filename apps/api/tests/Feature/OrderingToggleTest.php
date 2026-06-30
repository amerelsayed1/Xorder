<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class OrderingToggleTest extends TestCase
{
    use RefreshDatabase;

    public function test_restaurants_default_to_ordering_enabled(): void
    {
        // The factory doesn't set the column, so this asserts the DB default.
        $r = Restaurant::factory()->create();

        $this->assertTrue($r->fresh()->ordering_enabled);
        $this->assertDatabaseHas('restaurants', ['id' => $r->id, 'ordering_enabled' => true]);
    }

    public function test_super_admin_can_disable_ordering(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create(['ordering_enabled' => true]);

        $this->actingAs($sa)->putJson("/api/admin/restaurants/{$r->id}", ['ordering_enabled' => false])
            ->assertOk()
            ->assertJsonPath('data.ordering_enabled', false);

        $this->assertDatabaseHas('restaurants', ['id' => $r->id, 'ordering_enabled' => false]);
    }

    public function test_public_menu_exposes_ordering_flag(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'view-only', 'ordering_enabled' => false]);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/view-only/menu')
            ->assertOk()
            ->assertJsonPath('available', true)
            ->assertJsonPath('data.restaurant.ordering_enabled', false);
    }

    public function test_ordering_flag_is_not_writable_by_restaurant_admin(): void
    {
        $r = Restaurant::factory()->create(['ordering_enabled' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // The admin restaurant-update route is SUPER_ADMIN only.
        $this->actingAs($admin)->putJson("/api/admin/restaurants/{$r->id}", ['ordering_enabled' => false])
            ->assertForbidden();

        $this->assertDatabaseHas('restaurants', ['id' => $r->id, 'ordering_enabled' => true]);
    }
}

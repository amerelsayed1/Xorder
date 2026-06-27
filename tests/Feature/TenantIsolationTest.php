<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TenantIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_routes_forbidden_for_restaurant_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/admin/restaurants')->assertForbidden();
    }

    public function test_restaurant_admin_only_sees_own_categories(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();
        Category::factory()->for($a)->create(['name_en' => 'Mine']);
        Category::factory()->for($b)->create(['name_en' => 'Theirs']);

        $admin = User::factory()->restaurantAdmin($a->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/categories')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name_en', 'Mine');
    }

    public function test_restaurant_admin_cannot_read_other_restaurants_category(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();
        $othersCategory = Category::factory()->for($b)->create();

        $admin = User::factory()->restaurantAdmin($a->id)->create();

        // 404 (not 403): the scope makes it invisible, never disclosing existence.
        $this->actingAs($admin)->getJson("/api/dashboard/categories/{$othersCategory->id}")
            ->assertNotFound();
    }

    public function test_restaurant_admin_cannot_update_other_restaurants_item(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();
        $cat = Category::factory()->for($b)->create();
        $item = MenuItem::factory()->for($b)->for($cat)->create();

        $admin = User::factory()->restaurantAdmin($a->id)->create();

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", ['price' => 1])
            ->assertNotFound();
    }

    public function test_item_cannot_be_attached_to_another_restaurants_category(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();
        $foreignCat = Category::factory()->for($b)->create();

        $admin = User::factory()->restaurantAdmin($a->id)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $foreignCat->id,
            'name_en' => 'Hack', 'price' => 10,
        ])->assertStatus(422)->assertJsonValidationErrors('category_id');
    }
}

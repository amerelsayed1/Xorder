<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class CategoryAndItemTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $r = Restaurant::factory()->create();
        return User::factory()->restaurantAdmin($r->id)->create();
    }

    public function test_category_name_unique_within_restaurant(): void
    {
        $admin = $this->admin();
        Category::factory()->for($admin->restaurant)->create(['name_en' => 'Drinks']);

        $this->actingAs($admin)->postJson('/api/dashboard/categories', ['name_en' => 'Drinks'])
            ->assertStatus(422)->assertJsonValidationErrors('name_en');
    }

    public function test_category_requires_a_name(): void
    {
        $admin = $this->admin();

        $this->actingAs($admin)->postJson('/api/dashboard/categories', [])
            ->assertStatus(422)->assertJsonValidationErrors('name_en');
    }

    public function test_cannot_delete_category_with_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->deleteJson("/api/dashboard/categories/{$cat->id}")
            ->assertStatus(422);

        $this->assertDatabaseHas('categories', ['id' => $cat->id]);
    }

    public function test_item_price_cannot_be_negative(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'X', 'price' => -5,
        ])->assertStatus(422)->assertJsonValidationErrors('price');
    }

    public function test_discounted_price_must_be_lower_than_price(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'X', 'price' => 10, 'discounted_price' => 12,
        ])->assertStatus(422)->assertJsonValidationErrors('discounted_price');
    }

    public function test_toggle_item_availability(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create(['is_available' => true]);

        $this->actingAs($admin)->patchJson("/api/dashboard/items/{$item->id}/availability", ['is_available' => false])
            ->assertOk();

        $this->assertFalse($item->fresh()->is_available);
    }

    public function test_deleted_item_is_soft_deleted(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->deleteJson("/api/dashboard/items/{$item->id}")->assertOk();

        $this->assertSoftDeleted('menu_items', ['id' => $item->id]);
    }
}

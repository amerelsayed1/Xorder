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

    public function test_deleting_category_soft_deletes_it_and_cascades_to_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->deleteJson("/api/dashboard/categories/{$cat->id}")
            ->assertOk();

        // Both the category and its items are soft-deleted (recoverable), not gone.
        $this->assertSoftDeleted('categories', ['id' => $cat->id]);
        $this->assertSoftDeleted('menu_items', ['id' => $item->id]);
    }

    public function test_category_name_can_be_reused_after_delete(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create(['name_en' => 'Drinks']);

        $this->actingAs($admin)->deleteJson("/api/dashboard/categories/{$cat->id}")->assertOk();

        // The freed name is available again once the old category is soft-deleted.
        $this->actingAs($admin)->postJson('/api/dashboard/categories', ['name_en' => 'Drinks'])
            ->assertCreated();
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

    public function test_bulk_delete_soft_deletes_all_selected_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $items = MenuItem::factory()->count(3)->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)
            ->deleteJson('/api/dashboard/items/bulk', ['ids' => $items->pluck('id')->all()])
            ->assertOk();

        foreach ($items as $item) {
            $this->assertSoftDeleted('menu_items', ['id' => $item->id]);
        }
    }

    public function test_bulk_delete_rejects_ids_from_another_restaurant(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $mine = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        // An item owned by a different tenant — must not be deletable via the list.
        $otherRestaurant = Restaurant::factory()->create();
        $otherCat = Category::factory()->for($otherRestaurant)->create();
        $foreign = MenuItem::factory()->for($otherRestaurant)->for($otherCat)->create();

        $this->actingAs($admin)
            ->deleteJson('/api/dashboard/items/bulk', ['ids' => [$mine->id, $foreign->id]])
            ->assertStatus(422);

        // Whole request is rejected: neither the owned nor the foreign item is deleted.
        $this->assertDatabaseHas('menu_items', ['id' => $mine->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('menu_items', ['id' => $foreign->id, 'deleted_at' => null]);
    }

    public function test_bulk_delete_requires_ids(): void
    {
        $admin = $this->admin();

        $this->actingAs($admin)->deleteJson('/api/dashboard/items/bulk', ['ids' => []])
            ->assertStatus(422)->assertJsonValidationErrors('ids');
    }
}

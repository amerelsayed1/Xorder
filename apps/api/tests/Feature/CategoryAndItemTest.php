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

    public function test_a_variant_option_can_carry_a_sale_price_and_it_reaches_the_public_menu(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 100,
            'option_groups' => [[
                'name_en' => 'Size', 'is_variant' => true,
                'options' => [
                    ['name_en' => 'Large', 'price' => 120, 'discounted_price' => 100],
                    ['name_en' => 'Small', 'price' => 80],
                ],
            ]],
        ])->assertCreated();

        $slug = $admin->restaurant->slug;
        $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.option_groups.0.options.0.discounted_price', '100.00')
            // An undiscounted size stays null so the menu renders it unchanged.
            ->assertJsonPath('data.categories.0.items.0.option_groups.0.options.1.discounted_price', null);
    }

    public function test_a_variant_option_sale_price_must_be_lower_than_its_own_price(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 100,
            'option_groups' => [[
                'name_en' => 'Size', 'is_variant' => true,
                'options' => [['name_en' => 'Large', 'price' => 120, 'discounted_price' => 150]],
            ]],
        ])->assertStatus(422)
            ->assertJsonValidationErrors('option_groups.0.options.0.discounted_price');
    }

    public function test_a_sale_price_is_dropped_on_an_add_on_group(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        // An add-on price is a delta on top of the item, so a "sale price" on it
        // is meaningless — the server discards it rather than storing a figure
        // the menu would never use.
        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 100,
            'option_groups' => [[
                'name_en' => 'Extras', 'is_variant' => false,
                'options' => [['name_en' => 'Cheese', 'price' => 20, 'discounted_price' => 10]],
            ]],
        ])->assertCreated();

        $this->assertDatabaseHas('options', ['name_en' => 'Cheese', 'discounted_price' => null]);
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

    public function test_items_index_hides_items_of_inactive_categories(): void
    {
        $admin = $this->admin();
        $active = Category::factory()->for($admin->restaurant)->create(['is_active' => true]);
        $inactive = Category::factory()->for($admin->restaurant)->create(['is_active' => false]);
        $visible = MenuItem::factory()->for($admin->restaurant)->for($active)->create();
        $hidden = MenuItem::factory()->for($admin->restaurant)->for($inactive)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/items')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $visible->id)
            ->assertJsonMissing(['id' => $hidden->id]);
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

    public function test_bulk_delete_categories_soft_deletes_them_and_cascades_to_items(): void
    {
        $admin = $this->admin();
        $cats = Category::factory()->count(2)->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($admin->restaurant)->for($cats->first())->create();

        $this->actingAs($admin)
            ->deleteJson('/api/dashboard/categories/bulk', ['ids' => $cats->pluck('id')->all()])
            ->assertOk();

        foreach ($cats as $cat) {
            $this->assertSoftDeleted('categories', ['id' => $cat->id]);
        }
        // Items under a deleted category cascade too, matching single delete.
        $this->assertSoftDeleted('menu_items', ['id' => $item->id]);
    }

    public function test_bulk_delete_categories_rejects_ids_from_another_restaurant(): void
    {
        $admin = $this->admin();
        $mine = Category::factory()->for($admin->restaurant)->create();

        $otherRestaurant = Restaurant::factory()->create();
        $foreign = Category::factory()->for($otherRestaurant)->create();

        $this->actingAs($admin)
            ->deleteJson('/api/dashboard/categories/bulk', ['ids' => [$mine->id, $foreign->id]])
            ->assertStatus(422);

        // Whole request is rejected: neither category is deleted.
        $this->assertDatabaseHas('categories', ['id' => $mine->id, 'deleted_at' => null]);
        $this->assertDatabaseHas('categories', ['id' => $foreign->id, 'deleted_at' => null]);
    }

    public function test_bulk_delete_categories_requires_ids(): void
    {
        $admin = $this->admin();

        $this->actingAs($admin)->deleteJson('/api/dashboard/categories/bulk', ['ids' => []])
            ->assertStatus(422)->assertJsonValidationErrors('ids');
    }

    public function test_variant_option_group_is_forced_single_select_and_required(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        // Client sends a variant group but also (wrongly) marks it optional and
        // multi-select — the server must clamp it to required + single-select.
        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Mini Pancake', 'price' => 80,
            'option_groups' => [[
                'name_en' => 'Pieces', 'is_variant' => true,
                'is_required' => false, 'max_select' => 5,
                'options' => [
                    ['name_en' => '12 pieces', 'price' => 80],
                    ['name_en' => '18 pieces', 'price' => 150],
                ],
            ]],
        ])->assertCreated();

        $this->assertDatabaseHas('option_groups', [
            'name_en' => 'Pieces', 'is_variant' => true, 'is_required' => true, 'max_select' => 1,
        ]);
    }

    public function test_public_menu_exposes_is_variant_flag(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Mini Pancake', 'price' => 80,
            'option_groups' => [[
                'name_en' => 'Pieces', 'is_variant' => true,
                'options' => [['name_en' => '12 pieces', 'price' => 80]],
            ]],
        ])->assertCreated();

        $slug = $admin->restaurant->slug;
        $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.option_groups.0.is_variant', true);
    }

    public function test_item_reorder_rejects_a_foreign_id_and_changes_nothing(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $mine = MenuItem::factory()->for($admin->restaurant)->for($cat)->create(['display_order' => 1]);

        $other = $this->admin();
        $otherCat = Category::factory()->for($other->restaurant)->create();
        $foreign = MenuItem::factory()->for($other->restaurant)->for($otherCat)->create(['display_order' => 5]);

        // A payload mixing an owned id with a foreign one must be rejected wholesale
        // (422), not silently drop the foreign row and reorder the rest.
        $this->actingAs($admin)->patchJson('/api/dashboard/items/reorder', [
            'order' => [
                ['id' => $mine->id, 'display_order' => 2],
                ['id' => $foreign->id, 'display_order' => 3],
            ],
        ])->assertStatus(422);

        $this->assertSame(1, $mine->fresh()->display_order);
        $this->assertSame(5, $foreign->fresh()->display_order);
    }
}

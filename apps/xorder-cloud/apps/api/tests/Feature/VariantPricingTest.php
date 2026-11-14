<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * An item with a size (variant) group is not priced by menu_items.price — the
 * chosen size replaces it, and the menu pre-selects the first size. So the
 * item's advertised price must equal that default size, everywhere: the stored
 * column, the dashboard, and the public menu card.
 */
class VariantPricingTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $r = Restaurant::factory()->create();

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    /** Small 50 / Med 100 / Large 150 — the classic case. */
    private function sizes(array $options): array
    {
        return [['name_en' => 'Size', 'is_variant' => true, 'options' => $options]];
    }

    public function test_item_price_mirrors_the_first_size_not_the_submitted_price(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 999,
            'option_groups' => $this->sizes([
                ['name_en' => 'Small', 'price' => 50],
                ['name_en' => 'Med', 'price' => 100],
                ['name_en' => 'Large', 'price' => 150],
            ]),
        ])->assertCreated()->assertJsonPath('data.price', '50.00');

        $this->assertSame('50.00', MenuItem::firstWhere('name_en', 'Pizza')->price);
    }

    public function test_the_first_size_is_the_default_even_when_it_is_not_the_cheapest(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 10,
            'option_groups' => $this->sizes([
                ['name_en' => 'Large', 'price' => 150],
                ['name_en' => 'Small', 'price' => 50],
            ]),
        ])->assertCreated()->assertJsonPath('data.price', '150.00');
    }

    public function test_the_default_size_sale_price_becomes_the_item_discount(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 10,
            'option_groups' => $this->sizes([
                ['name_en' => 'Small', 'price' => 50, 'discounted_price' => 40],
                ['name_en' => 'Large', 'price' => 150],
            ]),
        ])->assertCreated()
            ->assertJsonPath('data.price', '50.00')
            ->assertJsonPath('data.discounted_price', '40.00');
    }

    /** An unavailable size is hidden from the menu, so it cannot be the default. */
    public function test_an_unavailable_first_size_is_skipped(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 10,
            'option_groups' => $this->sizes([
                ['name_en' => 'Small', 'price' => 50, 'is_available' => false],
                ['name_en' => 'Med', 'price' => 100],
            ]),
        ])->assertCreated()->assertJsonPath('data.price', '100.00');
    }

    public function test_reordering_the_sizes_repricing_the_item(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $id = $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 10,
            'option_groups' => $this->sizes([
                ['name_en' => 'Small', 'price' => 50],
                ['name_en' => 'Large', 'price' => 150],
            ]),
        ])->assertCreated()->json('data.id');

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$id}", [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 50,
            'option_groups' => $this->sizes([
                ['name_en' => 'Large', 'price' => 150],
                ['name_en' => 'Small', 'price' => 50],
            ]),
        ])->assertOk()->assertJsonPath('data.price', '150.00');
    }

    /** A price-only edit must lose to the sizes rather than override them. */
    public function test_editing_the_price_alone_cannot_escape_the_sizes(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $id = $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 10,
            'option_groups' => $this->sizes([['name_en' => 'Small', 'price' => 50]]),
        ])->assertCreated()->json('data.id');

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$id}", [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 999,
        ])->assertOk()->assertJsonPath('data.price', '50.00');
    }

    public function test_an_item_without_sizes_keeps_its_own_price(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Juice', 'price' => 30, 'discounted_price' => 25,
            'option_groups' => [[
                'name_en' => 'Extras', 'is_variant' => false,
                'options' => [['name_en' => 'Ice', 'price' => 5]],
            ]],
        ])->assertCreated()
            ->assertJsonPath('data.price', '30.00')
            ->assertJsonPath('data.discounted_price', '25.00');
    }

    public function test_public_menu_card_quotes_the_default_size(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 999,
            'option_groups' => $this->sizes([
                ['name_en' => 'Small', 'price' => 50, 'discounted_price' => 40],
                ['name_en' => 'Large', 'price' => 150],
            ]),
        ])->assertCreated();

        $slug = $admin->restaurant->slug;
        $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.price', '50.00')
            ->assertJsonPath('data.categories.0.items.0.discounted_price', '40.00');
    }

    /** Library edits are live across every item, so prices must follow them. */
    public function test_editing_a_shared_size_group_reprices_the_items_using_it(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $groupId = $this->actingAs($admin)->postJson('/api/dashboard/option-groups', [
            'name_en' => 'Size', 'is_variant' => true, 'apply_scope' => 'items',
            'options' => [
                ['name_en' => 'Small', 'price' => 50],
                ['name_en' => 'Large', 'price' => 150],
            ],
        ])->assertCreated()->json('data.id');

        $itemId = $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Pizza', 'price' => 999,
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])->assertCreated()->assertJsonPath('data.price', '50.00')->json('data.id');

        $this->actingAs($admin)->putJson("/api/dashboard/option-groups/{$groupId}", [
            'name_en' => 'Size', 'is_variant' => true,
            'options' => [
                ['name_en' => 'Small', 'price' => 60],
                ['name_en' => 'Large', 'price' => 160],
            ],
        ])->assertOk();

        $this->assertSame('60.00', MenuItem::find($itemId)->price);
    }

    /** A restaurant-wide size group reaches items with no pivot row at all. */
    public function test_a_restaurant_wide_size_group_reprices_every_item(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($cat)->create(['price' => 999, 'restaurant_id' => $admin->restaurant_id]);

        $this->actingAs($admin)->postJson('/api/dashboard/option-groups', [
            'name_en' => 'Size', 'is_variant' => true, 'apply_scope' => 'all',
            'options' => [
                ['name_en' => 'Small', 'price' => 50],
                ['name_en' => 'Large', 'price' => 150],
            ],
        ])->assertCreated();

        $this->assertSame('50.00', $item->fresh()->price);
    }

    /** Cross-tenant guard: another restaurant's items are never touched. */
    public function test_a_shared_group_never_reprices_another_tenants_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        $other = $this->admin();
        $otherCat = Category::factory()->for($other->restaurant)->create();
        $otherItem = MenuItem::factory()->for($otherCat)->create([
            'price' => 999, 'restaurant_id' => $other->restaurant_id,
        ]);

        $this->actingAs($admin)->postJson('/api/dashboard/option-groups', [
            'name_en' => 'Size', 'is_variant' => true, 'apply_scope' => 'all',
            'options' => [['name_en' => 'Small', 'price' => 50]],
        ])->assertCreated();

        $this->assertSame('999.00', $otherItem->fresh()->price);
    }
}

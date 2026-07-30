<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class GlobalExtrasTest extends TestCase
{
    use RefreshDatabase;

    private function admin(): User
    {
        $r = Restaurant::factory()->create();

        return User::factory()->restaurantAdmin($r->id)->create();
    }

    /** Create a global (library) option group through the API and return its id. */
    private function createGlobalGroup(User $admin, array $overrides = []): int
    {
        $payload = array_merge([
            'name_en' => 'Extra cheese', 'name_ar' => 'جبنة إضافية',
            'max_select' => 3,
            'options' => [
                ['name_en' => 'Cheddar', 'price' => 5],
                ['name_en' => 'Mozzarella', 'price' => 8],
            ],
        ], $overrides);

        $res = $this->actingAs($admin)->postJson('/api/dashboard/option-groups', $payload)
            ->assertCreated();

        return $res->json('data.id');
    }

    public function test_create_global_group_stores_it_as_global_with_options(): void
    {
        $admin = $this->admin();
        $id = $this->createGlobalGroup($admin);

        $this->assertDatabaseHas('option_groups', [
            'id' => $id, 'is_global' => true, 'menu_item_id' => null,
            'restaurant_id' => $admin->restaurant_id,
        ]);
        $this->assertDatabaseCount('options', 2);
    }

    public function test_library_group_requires_a_name(): void
    {
        $admin = $this->admin();

        $this->actingAs($admin)->postJson('/api/dashboard/option-groups', ['options' => []])
            ->assertStatus(422)->assertJsonValidationErrors('name_ar');
    }

    public function test_index_reports_usage_count(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        // Attach the shared group to the item.
        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])->assertOk();

        $this->actingAs($admin)->getJson('/api/dashboard/option-groups')
            ->assertOk()
            ->assertJsonPath('data.0.id', $groupId)
            ->assertJsonPath('data.0.items_count', 1);
    }

    public function test_attaching_shared_group_creates_pivot_and_returns_is_global(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])
            ->assertOk()
            ->assertJsonPath('data.option_groups.0.is_global', true)
            ->assertJsonPath('data.option_groups.0.id', $groupId);

        $this->assertDatabaseHas('menu_item_option_group', [
            'menu_item_id' => $item->id, 'option_group_id' => $groupId,
            'restaurant_id' => $admin->restaurant_id, 'sort_order' => 0,
        ]);
    }

    public function test_editing_shared_group_is_live_across_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin, ['name_en' => 'Sauces', 'name_ar' => 'الصلصات', 'options' => [['name_en' => 'Ketchup', 'price' => 0]]]);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create(['is_featured' => true, 'is_available' => true]);

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])->assertOk();

        // Rename the library group — no touching the item.
        $this->actingAs($admin)->putJson("/api/dashboard/option-groups/{$groupId}", [
            'name_en' => 'Dips', 'name_ar' => 'صلصات',
            'options' => [['name_en' => 'Ketchup', 'price' => 0], ['name_en' => 'Garlic', 'price' => 3]],
        ])->assertOk();

        // The item (and the public menu) reflect the change instantly.
        $slug = $admin->restaurant->slug;
        $this->getJson("/api/public/restaurants/{$slug}/menu")
            ->assertOk()
            ->assertJsonPath('data.categories.0.items.0.option_groups.0.name_en', 'Dips')
            ->assertJsonCount(2, 'data.categories.0.items.0.option_groups.0.options');
    }

    public function test_detaching_shared_group_keeps_the_library_group(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])->assertOk();

        // Save the item again with no groups — detaches, but the library survives.
        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [],
        ])->assertOk();

        $this->assertDatabaseMissing('menu_item_option_group', ['menu_item_id' => $item->id]);
        $this->assertDatabaseHas('option_groups', ['id' => $groupId, 'is_global' => true]);
    }

    public function test_inline_and_shared_groups_keep_their_order(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin, ['name_en' => 'Shared', 'name_ar' => 'مشترك', 'options' => []]);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        // Order: inline first, shared second.
        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [
                ['ref' => 'inline', 'name_en' => 'Inline', 'options' => [['name_en' => 'A', 'price' => 1]]],
                ['ref' => 'shared', 'option_group_id' => $groupId],
            ],
        ])
            ->assertOk()
            ->assertJsonPath('data.option_groups.0.name_en', 'Inline')
            ->assertJsonPath('data.option_groups.0.is_global', false)
            ->assertJsonPath('data.option_groups.1.name_en', 'Shared')
            ->assertJsonPath('data.option_groups.1.is_global', true);
    }

    public function test_deleting_library_group_detaches_it_from_items(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $groupId = $this->createGlobalGroup($admin);
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $groupId]],
        ])->assertOk();

        $this->actingAs($admin)->deleteJson("/api/dashboard/option-groups/{$groupId}")->assertOk();

        $this->assertDatabaseMissing('option_groups', ['id' => $groupId]);
        $this->assertDatabaseMissing('menu_item_option_group', ['option_group_id' => $groupId]);
        // The item itself is untouched.
        $this->assertDatabaseHas('menu_items', ['id' => $item->id, 'deleted_at' => null]);
    }

    public function test_cannot_attach_a_group_from_another_restaurant(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();
        $item = MenuItem::factory()->for($admin->restaurant)->for($cat)->create();

        // A global group owned by a different tenant.
        $other = $this->admin();
        $foreignGroupId = $this->createGlobalGroup($other);

        $this->actingAs($admin)->putJson("/api/dashboard/items/{$item->id}", [
            'option_groups' => [['ref' => 'shared', 'option_group_id' => $foreignGroupId]],
        ])->assertOk();

        // The foreign id is silently ignored — no cross-tenant pivot is written.
        $this->assertDatabaseMissing('menu_item_option_group', [
            'menu_item_id' => $item->id, 'option_group_id' => $foreignGroupId,
        ]);
    }

    public function test_cannot_manage_a_group_from_another_restaurant(): void
    {
        $admin = $this->admin();
        $other = $this->admin();
        $foreignGroupId = $this->createGlobalGroup($other);

        // Route binding is tenant-scoped → cross-tenant access is a 404.
        $this->actingAs($admin)->getJson("/api/dashboard/option-groups/{$foreignGroupId}")->assertNotFound();
        $this->actingAs($admin)->putJson("/api/dashboard/option-groups/{$foreignGroupId}", ['name_en' => 'Hack'])->assertNotFound();
        $this->actingAs($admin)->deleteJson("/api/dashboard/option-groups/{$foreignGroupId}")->assertNotFound();
    }

    public function test_library_endpoint_rejects_an_inline_group_id(): void
    {
        $admin = $this->admin();
        $cat = Category::factory()->for($admin->restaurant)->create();

        // Create an item with an inline (non-global) group.
        $res = $this->actingAs($admin)->postJson('/api/dashboard/items', [
            'category_id' => $cat->id, 'name_en' => 'Burger', 'price' => 50,
            'option_groups' => [['name_en' => 'Inline', 'options' => [['name_en' => 'X', 'price' => 1]]]],
        ])->assertCreated();

        $inlineId = OptionGroup::where('menu_item_id', $res->json('data.id'))->value('id');

        // The library endpoints only act on global groups → 404 for an inline id.
        $this->actingAs($admin)->putJson("/api/dashboard/option-groups/{$inlineId}", ['name_en' => 'Nope'])
            ->assertNotFound();
        $this->actingAs($admin)->deleteJson("/api/dashboard/option-groups/{$inlineId}")
            ->assertNotFound();
    }
}

<?php

namespace Tests\Feature;

use App\Enums\TenantCapability as Cap;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Permissions are per-verb: a role can be allowed to add menu items without
 * being allowed to delete them. These cases pin each verb as *independent* —
 * holding one must not smuggle in another — which is the entire reason the old
 * blanket `manage` was split.
 */
class CapabilityVerbsTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Category $category;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create();
        $this->category = Category::factory()->for($this->restaurant)->create();
    }

    /** @param  list<Cap>  $caps */
    private function actor(array $caps): User
    {
        $role = new Role(['name' => 'Scoped '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => Cap::expand(array_map(fn (Cap $c) => $c->value, $caps)),
        ])->save();

        return User::factory()->staff($this->restaurant->id, $role->id)->create();
    }

    /** @param  list<string>  $keys */
    private function enableFeatures(array $keys): void
    {
        foreach ($keys as $key) {
            $this->restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }
        $this->restaurant->load('features');
    }

    private function item(): MenuItem
    {
        return MenuItem::factory()->for($this->restaurant)->for($this->category)->create();
    }

    // ------------------------------------------------------------------ menu

    public function test_create_allows_adding_but_not_editing_or_deleting(): void
    {
        $actor = $this->actor([Cap::MENU_CREATE]);
        $item = $this->item();

        $this->actingAs($actor)
            ->postJson('/api/dashboard/items', ['name_en' => 'New', 'price' => 10, 'category_id' => $this->category->id])
            ->assertCreated();

        $this->actingAs($actor)
            ->putJson("/api/dashboard/items/{$item->id}", ['name_en' => 'Edited', 'price' => 12, 'category_id' => $this->category->id])
            ->assertForbidden();

        $this->actingAs($actor)->deleteJson("/api/dashboard/items/{$item->id}")->assertForbidden();
    }

    public function test_update_allows_editing_but_not_adding_or_deleting(): void
    {
        $actor = $this->actor([Cap::MENU_UPDATE]);
        $item = $this->item();

        $this->actingAs($actor)
            ->putJson("/api/dashboard/items/{$item->id}", ['name_en' => 'Edited', 'price' => 12, 'category_id' => $this->category->id])
            ->assertOk();

        $this->actingAs($actor)
            ->postJson('/api/dashboard/items', ['name_en' => 'New', 'price' => 10, 'category_id' => $this->category->id])
            ->assertForbidden();

        $this->actingAs($actor)->deleteJson("/api/dashboard/items/{$item->id}")->assertForbidden();
    }

    /** The case that motivated the split: edit the menu freely, never wipe it. */
    public function test_delete_is_a_separate_grant(): void
    {
        $editor = $this->actor([Cap::MENU_CREATE, Cap::MENU_UPDATE]);
        $item = $this->item();

        $this->actingAs($editor)->deleteJson("/api/dashboard/items/{$item->id}")->assertForbidden();
        $this->assertModelExists($item);

        $remover = $this->actor([Cap::MENU_DELETE]);
        $this->actingAs($remover)->deleteJson("/api/dashboard/items/{$item->id}")->assertOk();
        // Menu items are soft-deleted — gone from the menu, retained for the
        // order snapshots that reference them.
        $this->assertSoftDeleted($item);
    }

    public function test_bulk_delete_needs_the_delete_verb_too(): void
    {
        $item = $this->item();

        $this->actingAs($this->actor([Cap::MENU_CREATE, Cap::MENU_UPDATE]))
            ->deleteJson('/api/dashboard/items/bulk', ['ids' => [$item->id]])
            ->assertForbidden();

        $this->actingAs($this->actor([Cap::MENU_DELETE]))
            ->deleteJson('/api/dashboard/items/bulk', ['ids' => [$item->id]])
            ->assertOk();
    }

    /** Reordering and toggling availability are edits, not creations. */
    public function test_reorder_and_availability_count_as_update(): void
    {
        $item = $this->item();

        $this->actingAs($this->actor([Cap::MENU_CREATE]))
            ->patchJson("/api/dashboard/items/{$item->id}/availability", ['is_available' => false])
            ->assertForbidden();

        $this->actingAs($this->actor([Cap::MENU_UPDATE]))
            ->patchJson("/api/dashboard/items/{$item->id}/availability", ['is_available' => false])
            ->assertOk();
    }

    // ----------------------------------------------------------------- reads

    public function test_every_verb_implies_its_own_view(): void
    {
        // Granting delete without view would leave someone able to remove a
        // section they cannot open.
        foreach ([Cap::MENU_CREATE, Cap::MENU_UPDATE, Cap::MENU_DELETE] as $cap) {
            $this->actingAs($this->actor([$cap]))
                ->getJson('/api/dashboard/items')
                ->assertOk();
        }
    }

    public function test_view_alone_grants_no_writes(): void
    {
        $actor = $this->actor([Cap::MENU_VIEW]);
        $item = $this->item();

        $this->actingAs($actor)->getJson('/api/dashboard/items')->assertOk();
        $this->actingAs($actor)
            ->postJson('/api/dashboard/items', ['name_en' => 'No', 'price' => 1, 'category_id' => $this->category->id])
            ->assertForbidden();
        $this->actingAs($actor)->deleteJson("/api/dashboard/items/{$item->id}")->assertForbidden();
    }

    // -------------------------------------------------------- other resources

    public function test_staff_verbs_are_independent(): void
    {
        $target = $this->actor([Cap::MENU_VIEW]);

        // Can list staff and create, but not delete.
        $creator = $this->actor([Cap::STAFF_CREATE]);
        $this->actingAs($creator)->getJson('/api/dashboard/staff')->assertOk();
        $this->actingAs($creator)->deleteJson("/api/dashboard/staff/{$target->id}")->assertForbidden();

        $remover = $this->actor([Cap::STAFF_DELETE]);
        $this->actingAs($remover)
            ->postJson('/api/dashboard/staff', ['name' => 'X', 'username' => 'x.person', 'role_id' => $target->role_id])
            ->assertForbidden();
    }

    /** The owner keeps implicit access to every verb. */
    public function test_the_owner_holds_all_verbs_without_a_role(): void
    {
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $item = $this->item();

        $this->actingAs($owner)
            ->postJson('/api/dashboard/items', ['name_en' => 'Owner', 'price' => 10, 'category_id' => $this->category->id])
            ->assertCreated();
        $this->actingAs($owner)->deleteJson("/api/dashboard/items/{$item->id}")->assertOk();
    }

    /** A role saved before the split keeps exactly the access it had. */
    public function test_a_legacy_manage_value_still_grants_all_three_verbs(): void
    {
        $expanded = Cap::expand(['menu.manage']);

        $this->assertSame(
            ['menu.view', 'menu.create', 'menu.update', 'menu.delete'],
            $expanded,
        );
    }

    // --------------------------------------------- live board (retired)

    /**
     * live-board-to-pos D9/D11: `live.view` no longer exists. The three reads it
     * used to unlock now need their own view capability and nothing else.
     */
    public function test_each_board_read_needs_its_own_view_capability(): void
    {
        $this->enableFeatures(['system_ordering', 'bill_requests', 'table_management']);

        $orders = $this->actor([Cap::ORDERS_VIEW]);
        $this->actingAs($orders)->getJson('/api/dashboard/orders')->assertOk();
        $this->actingAs($orders)->getJson('/api/dashboard/bill-requests')->assertForbidden();
        $this->actingAs($orders)->getJson('/api/dashboard/tables/live')->assertForbidden();

        $bills = $this->actor([Cap::BILLS_VIEW]);
        $this->actingAs($bills)->getJson('/api/dashboard/bill-requests')->assertOk();
        $this->actingAs($bills)->getJson('/api/dashboard/orders')->assertForbidden();
    }

    /** A role row that still carries the removed value (before the migration ran) grants nothing. */
    public function test_a_stale_live_view_value_in_a_role_grants_nothing(): void
    {
        $this->enableFeatures(['system_ordering', 'bill_requests', 'table_management']);

        $role = new Role(['name' => 'Stale']);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => ['live.view'],
            'is_system' => false,
        ])->save();
        $actor = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($actor)->getJson('/api/dashboard/orders')->assertForbidden();
        $this->actingAs($actor)->getJson('/api/dashboard/bill-requests')->assertForbidden();
        $this->actingAs($actor)->getJson('/api/dashboard/tables/live')->assertForbidden();
    }

    // ------------------------------------------------- deploy-window aliases

    /**
     * A dashboard tab loaded before the verb split gates its sidebar on the old
     * `<resource>.manage` names. /auth/me keeps publishing those alongside the
     * verbs for one release so those tabs do not lose Settings and Staff the
     * moment this deploys.
     */
    public function test_me_publishes_legacy_aliases_for_roles_that_hold_the_whole_verb_set(): void
    {
        $actor = $this->actor([Cap::MENU_CREATE, Cap::MENU_UPDATE, Cap::MENU_DELETE]);

        $caps = $this->actingAs($actor)->getJson('/api/auth/me')->assertOk()->json('data.capabilities');

        $this->assertContains('menu.create', $caps);
        $this->assertContains('menu.manage', $caps);
    }

    /** A partial grant must NOT claim the old blanket name. */
    public function test_a_partial_verb_set_does_not_get_the_legacy_alias(): void
    {
        // Add and edit, but not delete — "menu.manage" would overstate this.
        $actor = $this->actor([Cap::MENU_CREATE, Cap::MENU_UPDATE]);

        $caps = $this->actingAs($actor)->getJson('/api/auth/me')->assertOk()->json('data.capabilities');

        $this->assertContains('menu.update', $caps);
        $this->assertNotContains('menu.manage', $caps);
    }

    /** The owner holds everything, so every alias comes along. */
    public function test_the_owner_gets_every_legacy_alias(): void
    {
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();

        $caps = $this->actingAs($owner)->getJson('/api/auth/me')->assertOk()->json('data.capabilities');

        foreach (['settings.manage', 'staff.manage', 'menu.manage', 'tables.manage'] as $legacy) {
            $this->assertContains($legacy, $caps, "owner should still advertise {$legacy}");
        }
    }

    /** Aliases are advertised only — they must not open a gate on their own. */
    public function test_a_legacy_alias_does_not_authorise_anything_server_side(): void
    {
        $actor = $this->actor([Cap::MENU_VIEW]);

        // menu.view alone: no alias, and no write access.
        $this->actingAs($actor)
            ->postJson('/api/dashboard/items', ['name_en' => 'No', 'price' => 1, 'category_id' => $this->category->id])
            ->assertForbidden();
    }
}

<?php

namespace Tests\Feature;

use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\RestaurantProvisioningService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Fine-grained in-restaurant permissions: custom roles, staff accounts, and the
 * `can:<tenant capability>` gates on /api/dashboard.
 *
 * The three properties worth defending here are (1) a staff account can only do
 * what its role lists, (2) nobody can grant themselves — or someone else — more
 * than they already hold, and (3) none of it leaks across tenants.
 */
class TenantRbacTest extends TestCase
{
    use RefreshDatabase;

    /** @param  list<TenantCapability>  $capabilities */
    private function role(Restaurant $restaurant, string $name, array $capabilities, bool $system = false): Role
    {
        $role = new Role(['name' => $name]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand(array_map(fn ($c) => $c->value, $capabilities)),
            'is_system' => $system,
        ])->save();

        return $role;
    }

    private function staff(Restaurant $restaurant, Role $role, array $attributes = []): User
    {
        return User::factory()->staff($restaurant->id, $role->id)->create($attributes);
    }

    // ---------------------------------------------------------------- seeding

    public function test_provisioning_seeds_only_the_admin_role(): void
    {
        ['restaurant' => $restaurant] = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'Seeded', 'slug' => 'seeded'],
            ['name' => 'Owner', 'username' => 'owner', 'email' => 'owner@example.test'],
        );

        $roles = Role::where('restaurant_id', $restaurant->id)->get();

        // Exactly one seeded role, and it is the unrestricted one. Narrower
        // roles are the owner's to invent, not ours to guess.
        $this->assertCount(1, $roles);
        $this->assertSame('admin', $roles->first()->slug);
        $this->assertTrue($roles->first()->is_system);

        // "Access to the whole system" means every capability, staff.manage
        // included — it is the tenant-side twin of the owner's own access.
        $this->assertEqualsCanonicalizing(
            TenantCapability::values(),
            $roles->first()->capabilities,
        );
    }

    /** The one protected role is the only thing standing between a tenant and no roles at all. */
    public function test_the_admin_role_cannot_be_deleted(): void
    {
        ['restaurant' => $restaurant] = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'Seeded', 'slug' => 'seeded2'],
            ['name' => 'Owner', 'username' => 'owner2', 'email' => 'owner2@example.test'],
        );

        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $admin = Role::where('restaurant_id', $restaurant->id)->where('slug', 'admin')->first();

        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$admin->id}")->assertStatus(422);
        $this->assertDatabaseHas('roles', ['id' => $admin->id]);
    }

    /** Anything the owner creates themselves stays theirs to remove. */
    public function test_a_role_the_owner_created_can_be_deleted(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $role = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);

        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$role->id}")->assertOk();
        $this->assertDatabaseMissing('roles', ['id' => $role->id]);
    }

    // ------------------------------------------------------------ route gates

    public function test_owner_holds_every_capability_implicitly(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        foreach (TenantCapability::active() as $capability) {
            $this->assertTrue($owner->can($capability->value), $capability->value);
        }

        $this->actingAs($owner)->getJson('/api/dashboard/staff')->assertOk();
        $this->actingAs($owner)->getJson('/api/dashboard/roles')->assertOk();
    }

    public function test_staff_can_read_only_what_their_role_grants(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Kitchen', [TenantCapability::MENU_VIEW]);
        $cook = $this->staff($restaurant, $role);
        Category::factory()->for($restaurant)->create();

        $this->actingAs($cook)->getJson('/api/dashboard/items')->assertOk();
        $this->actingAs($cook)->getJson('/api/dashboard/customers')->assertForbidden();
        $this->actingAs($cook)->getJson('/api/dashboard/staff')->assertForbidden();
        $this->actingAs($cook)->getJson('/api/dashboard/roles')->assertForbidden();
    }

    public function test_view_capability_does_not_imply_write(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Reader', [TenantCapability::MENU_VIEW]);
        $reader = $this->staff($restaurant, $role);
        $category = Category::factory()->for($restaurant)->create();

        $this->actingAs($reader)
            ->postJson('/api/dashboard/items', ['name_en' => 'Nope', 'price' => 10, 'category_id' => $category->id])
            ->assertForbidden();

        $this->assertSame(0, MenuItem::where('restaurant_id', $restaurant->id)->count());
    }

    public function test_the_create_verb_allows_the_write(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Menu adder', [TenantCapability::MENU_CREATE]);
        $editor = $this->staff($restaurant, $role);
        $category = Category::factory()->for($restaurant)->create();

        $this->actingAs($editor)
            ->postJson('/api/dashboard/items', ['name_en' => 'Yes', 'price' => 10, 'category_id' => $category->id])
            ->assertCreated();
    }

    public function test_shell_endpoints_stay_open_to_every_tenant_account(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Minimal', [TenantCapability::MENU_VIEW]);
        $staff = $this->staff($restaurant, $role);

        // The dashboard shell must render for anyone who can sign in at all.
        $this->actingAs($staff)->getJson('/api/dashboard/pulse')->assertOk();
        $this->actingAs($staff)->getJson('/api/dashboard/notifications')->assertOk();
    }

    public function test_pulse_zeroes_counts_the_user_may_not_open(): void
    {
        $restaurant = Restaurant::factory()->create();
        $restaurant->features()->create(['feature_key' => 'system_ordering', 'is_enabled' => true]);
        $role = $this->role($restaurant, 'Menu only', [TenantCapability::MENU_VIEW]);
        $staff = $this->staff($restaurant, $role);

        $this->actingAs($staff)->getJson('/api/dashboard/pulse')
            ->assertOk()
            ->assertJsonPath('data.new_orders', null);
    }

    public function test_suspended_staff_are_refused(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::ORDERS_UPDATE]);
        $staff = $this->staff($restaurant, $role, ['status' => UserStatus::SUSPENDED]);

        $this->actingAs($staff)->getJson('/api/dashboard/pulse')->assertForbidden();
    }

    public function test_staff_cannot_reach_the_admin_panel(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Manager', TenantCapability::cases());
        $manager = $this->staff($restaurant, $role);

        $this->actingAs($manager)->getJson('/api/admin/restaurants')->assertForbidden();
    }

    // ----------------------------------------------------------- staff CRUD

    public function test_owner_creates_staff_scoped_to_their_restaurant(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $role = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);

        $response = $this->actingAs($owner)->postJson('/api/dashboard/staff', [
            'name' => 'Sara', 'username' => 'sara', 'role_id' => $role->id,
        ])->assertCreated();

        $created = User::where('username', 'sara')->firstOrFail();
        $this->assertSame(RoleEnum::RESTAURANT_STAFF, $created->role);
        $this->assertSame($restaurant->id, $created->restaurant_id);
        $this->assertSame($role->id, $created->role_id);
        // No password supplied → one is generated and handed back exactly once.
        $this->assertNotEmpty($response->json('generated_password'));
    }

    public function test_staff_creation_ignores_a_forged_restaurant_or_role(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($mine->id)->create();
        $myRole = $this->role($mine, 'Waiter', [TenantCapability::ORDERS_UPDATE]);
        $theirRole = $this->role($theirs, 'Waiter', [TenantCapability::ORDERS_UPDATE]);

        // A role id from another tenant does not exist as far as this form is concerned.
        $this->actingAs($owner)->postJson('/api/dashboard/staff', [
            'name' => 'Mole', 'username' => 'mole', 'role_id' => $theirRole->id,
        ])->assertStatus(422)->assertJsonValidationErrors('role_id');

        // restaurant_id in the payload is ignored: the tenant comes from the actor.
        $this->actingAs($owner)->postJson('/api/dashboard/staff', [
            'name' => 'Sara', 'username' => 'sara', 'role_id' => $myRole->id,
            'restaurant_id' => $theirs->id, 'role' => 'RESTAURANT_ADMIN',
        ])->assertCreated();

        $created = User::where('username', 'sara')->firstOrFail();
        $this->assertSame($mine->id, $created->restaurant_id);
        $this->assertSame(RoleEnum::RESTAURANT_STAFF, $created->role);
    }

    /**
     * The owner now appears in the listing (see the owner-row cases below), but
     * the *actionable* surface is unchanged: another tenant is invisible, and
     * the owner account remains untouchable through these endpoints.
     */
    public function test_staff_endpoint_never_exposes_another_tenant(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($mine->id)->create();
        $myStaff = $this->staff($mine, $this->role($mine, 'Waiter', [TenantCapability::ORDERS_VIEW]));
        $theirStaff = $this->staff($theirs, $this->role($theirs, 'Waiter', [TenantCapability::ORDERS_VIEW]));

        $rows = $this->actingAs($owner)->getJson('/api/dashboard/staff')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->json('data');

        // My owner and my staff — and nobody else's.
        $this->assertEqualsCanonicalizing(
            [$owner->id, $myStaff->id],
            array_column($rows, 'id'),
        );

        // 404, not 403: cross-tenant ids and the owner account are invisible here.
        $this->actingAs($owner)->getJson("/api/dashboard/staff/{$theirStaff->id}")->assertNotFound();
        $this->actingAs($owner)->getJson("/api/dashboard/staff/{$owner->id}")->assertNotFound();
        $this->actingAs($owner)->deleteJson("/api/dashboard/staff/{$theirStaff->id}")->assertNotFound();

        $this->assertDatabaseHas('users', ['id' => $theirStaff->id]);
    }

    public function test_a_manager_cannot_delete_their_own_account(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Manager', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE]);
        $manager = $this->staff($restaurant, $role);

        $this->actingAs($manager)->deleteJson("/api/dashboard/staff/{$manager->id}")->assertForbidden();
        $this->assertDatabaseHas('users', ['id' => $manager->id]);
    }

    public function test_password_reset_invalidates_older_tokens(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $staff = $this->staff($restaurant, $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_VIEW]));
        $before = $staff->password_changed_at;

        $this->actingAs($owner)->postJson("/api/dashboard/staff/{$staff->id}/reset-password")
            ->assertOk()
            ->assertJsonStructure(['generated_password']);

        $this->assertTrue($staff->fresh()->password_changed_at->greaterThan($before ?? now()->subDay()));
    }

    // ----------------------------------------------------------- role CRUD

    public function test_creating_a_role_expands_manage_into_view(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->actingAs($owner)->postJson('/api/dashboard/roles', [
            'name' => 'Floor', 'capabilities' => [TenantCapability::ORDERS_UPDATE->value],
        ])->assertCreated();

        $role = Role::where('restaurant_id', $restaurant->id)->firstOrFail();
        $this->assertEqualsCanonicalizing(
            [TenantCapability::ORDERS_VIEW->value, TenantCapability::ORDERS_UPDATE->value],
            $role->capabilities,
        );
        $this->assertFalse($role->is_system);
    }

    public function test_a_manager_cannot_grant_capabilities_they_lack(): void
    {
        $restaurant = Restaurant::factory()->create();
        // Holds staff.manage but nothing else — the interesting case.
        $role = $this->role($restaurant, 'HR', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE]);
        $manager = $this->staff($restaurant, $role);

        $this->actingAs($manager)->postJson('/api/dashboard/roles', [
            'name' => 'Superuser', 'capabilities' => [TenantCapability::SETTINGS_UPDATE->value],
        ])->assertStatus(422)->assertJsonValidationErrors('capabilities');

        $this->assertSame(1, Role::where('restaurant_id', $restaurant->id)->count());
    }

    public function test_a_manager_cannot_assign_a_role_stronger_than_their_own(): void
    {
        $restaurant = Restaurant::factory()->create();
        $hr = $this->role($restaurant, 'HR', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE]);
        $powerful = $this->role($restaurant, 'Owner-ish', [TenantCapability::SETTINGS_UPDATE]);
        $manager = $this->staff($restaurant, $hr);

        $this->actingAs($manager)->postJson('/api/dashboard/staff', [
            'name' => 'Puppet', 'username' => 'puppet', 'role_id' => $powerful->id,
        ])->assertStatus(422)->assertJsonValidationErrors('role_id');

        $this->assertDatabaseMissing('users', ['username' => 'puppet']);
    }

    public function test_role_names_are_unique_per_restaurant_only(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $this->role($theirs, 'Cashier', [TenantCapability::ORDERS_UPDATE]);
        $owner = User::factory()->restaurantAdmin($mine->id)->create();

        // Another tenant already has a "Cashier" — irrelevant here.
        $this->actingAs($owner)->postJson('/api/dashboard/roles', [
            'name' => 'Cashier', 'capabilities' => [TenantCapability::ORDERS_UPDATE->value],
        ])->assertCreated();

        // A second one inside the same restaurant is not.
        $this->actingAs($owner)->postJson('/api/dashboard/roles', [
            'name' => 'Cashier', 'capabilities' => [TenantCapability::ORDERS_UPDATE->value],
        ])->assertStatus(422)->assertJsonValidationErrors('name');
    }

    public function test_system_roles_cannot_be_deleted(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $preset = $this->role($restaurant, 'Manager', [TenantCapability::ORDERS_UPDATE], system: true);

        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$preset->id}")->assertStatus(422);
        $this->assertDatabaseHas('roles', ['id' => $preset->id]);
    }

    public function test_a_role_in_use_must_be_reassigned_before_deletion(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $doomed = $this->role($restaurant, 'Doomed', [TenantCapability::ORDERS_UPDATE]);
        $replacement = $this->role($restaurant, 'Keeper', [TenantCapability::ORDERS_UPDATE]);
        $held = $this->staff($restaurant, $doomed);

        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$doomed->id}")
            ->assertStatus(422)
            ->assertJsonPath('users_count', 1);

        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$doomed->id}", ['reassign_to' => $replacement->id])
            ->assertOk();

        $this->assertDatabaseMissing('roles', ['id' => $doomed->id]);
        // Reassigned rather than blanked: a null role_id means no capabilities at all.
        $this->assertSame($replacement->id, $held->fresh()->role_id);
    }

    public function test_roles_are_invisible_across_tenants(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($mine->id)->create();
        $theirRole = $this->role($theirs, 'Theirs', [TenantCapability::ORDERS_UPDATE]);
        $this->role($mine, 'Mine', [TenantCapability::ORDERS_UPDATE]);

        $this->actingAs($owner)->getJson('/api/dashboard/roles')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Mine');

        $this->actingAs($owner)->getJson("/api/dashboard/roles/{$theirRole->id}")->assertNotFound();
        $this->actingAs($owner)->deleteJson("/api/dashboard/roles/{$theirRole->id}")->assertNotFound();
    }

    // --------------------------------------------------------------- identity

    public function test_me_reports_the_staff_capability_set(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::ORDERS_UPDATE]);
        $staff = $this->staff($restaurant, $role);

        $this->actingAs($staff)->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.role', 'RESTAURANT_STAFF')
            ->assertJsonPath('data.role_id', $role->id)
            ->assertJsonPath('data.role_name', 'Cashier');

        // The verbs the role actually holds. /auth/me also carries the legacy
        // `<resource>.manage` aliases during the deploy window (see
        // User::withLegacyAliases), so this asserts containment, not equality.
        $caps = $this->actingAs($staff)->getJson('/api/auth/me')->json('data.capabilities');

        $this->assertContains(TenantCapability::ORDERS_VIEW->value, $caps);
        $this->assertContains(TenantCapability::ORDERS_UPDATE->value, $caps);
        $this->assertNotContains(TenantCapability::MENU_VIEW->value, $caps);
    }

    public function test_owner_reports_the_full_capability_set(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $caps = $this->actingAs($owner)->getJson('/api/auth/me')
            ->assertOk()
            ->json('data.capabilities');

        // Every verb, plus the legacy aliases carried through the deploy window.
        foreach (TenantCapability::values() as $value) {
            $this->assertContains($value, $caps);
        }
    }

    public function test_staff_can_sign_in_with_a_username_and_no_email(): void
    {
        $restaurant = Restaurant::factory()->create(['slug' => 'alpha']);
        $role = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);
        $this->staff($restaurant, $role, [
            'username' => 'waiter1', 'email' => null, 'password' => 'floor-secret',
        ]);

        $this->postJson('http://alpha.example.com/api/auth/login', [
            'username' => 'waiter1', 'password' => 'floor-secret',
        ])->assertOk()->assertJsonPath('data.role', 'RESTAURANT_STAFF');
    }

    // ------------------------------------------------- branch list as reference data

    /**
     * A Cashier-shaped role holds tables.view but not branches.view, and the
     * dining-areas screen it can open has to resolve branch names and offer a
     * branch when creating — so the list has to be readable without granting
     * the branch section itself.
     */
    public function test_tables_view_can_read_the_branch_list_without_branches_view(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::TABLES_VIEW]);
        $staff = $this->staff($restaurant, $role);

        $this->assertNotContains(TenantCapability::BRANCHES_VIEW->value, $role->capabilities);

        $this->actingAs($staff)->getJson('/api/dashboard/branches')->assertOk();
    }

    /** The list stays closed to a role with neither capability. */
    public function test_a_role_with_neither_capability_cannot_read_the_branch_list(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Kitchen', [TenantCapability::ORDERS_VIEW]);

        $this->actingAs($this->staff($restaurant, $role))
            ->getJson('/api/dashboard/branches')
            ->assertForbidden();
    }

    /** Widening the list must not widen the Wi-Fi presence probe with it. */
    public function test_tables_view_still_cannot_read_branch_presence(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::TABLES_VIEW]);
        $branch = new Branch(['name_en' => 'Main']);
        $branch->forceFill(['restaurant_id' => $restaurant->id])->save();

        $this->actingAs($this->staff($restaurant, $role))
            ->getJson("/api/dashboard/branches/{$branch->id}/presence")
            ->assertForbidden();
    }

    // ------------------------------------------------ owners in the staff list

    /**
     * An Employees screen that hid the one person always present read as broken,
     * so owners are listed — but listing is all it is. Every write against an
     * owner still 404s, which is what stops a tenant locking itself out.
     */
    public function test_the_staff_list_includes_the_owner_marked_as_such(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create(['name' => 'The Owner']);
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::ORDERS_UPDATE]);
        $staff = $this->staff($restaurant, $role, ['name' => 'A Cashier']);

        $rows = $this->actingAs($owner)->getJson('/api/dashboard/staff')->assertOk()->json('data');

        $this->assertCount(2, $rows);
        // Owner first, so the list opens on the account that is always there.
        $this->assertSame($owner->id, $rows[0]['id']);
        $this->assertTrue($rows[0]['is_owner']);
        $this->assertNull($rows[0]['role_id']);

        $this->assertSame($staff->id, $rows[1]['id']);
        $this->assertFalse($rows[1]['is_owner']);
    }

    public function test_an_owner_cannot_be_edited_suspended_or_deleted_through_the_staff_endpoints(): void
    {
        $restaurant = Restaurant::factory()->create();
        $actingOwner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $otherOwner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $role = $this->role($restaurant, 'Cashier', [TenantCapability::ORDERS_UPDATE]);

        // 404, not 403: the owner account is invisible to these endpoints.
        $this->actingAs($actingOwner)->getJson("/api/dashboard/staff/{$otherOwner->id}")->assertNotFound();
        $this->actingAs($actingOwner)
            ->putJson("/api/dashboard/staff/{$otherOwner->id}", [
                'name' => 'Hijacked', 'username' => 'hijacked', 'role_id' => $role->id,
            ])
            ->assertNotFound();
        $this->actingAs($actingOwner)->deleteJson("/api/dashboard/staff/{$otherOwner->id}")->assertNotFound();
        $this->actingAs($actingOwner)
            ->postJson("/api/dashboard/staff/{$otherOwner->id}/reset-password")
            ->assertNotFound();

        $this->assertDatabaseHas('users', ['id' => $otherOwner->id, 'role' => 'RESTAURANT_ADMIN']);
    }

    /** Staff with staff.delete must not be able to remove the owner either. */
    public function test_staff_holding_delete_still_cannot_remove_the_owner(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $powerful = $this->role($restaurant, 'Manager', TenantCapability::cases());

        $this->actingAs($this->staff($restaurant, $powerful))
            ->deleteJson("/api/dashboard/staff/{$owner->id}")
            ->assertNotFound();

        $this->assertDatabaseHas('users', ['id' => $owner->id]);
    }

    /** Another tenant's owner never appears, listing or otherwise. */
    public function test_the_list_never_crosses_tenants(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $myOwner = User::factory()->restaurantAdmin($mine->id)->create();
        User::factory()->restaurantAdmin($theirs->id)->create();

        $rows = $this->actingAs($myOwner)->getJson('/api/dashboard/staff')->assertOk()->json('data');

        $this->assertCount(1, $rows);
        $this->assertSame($myOwner->id, $rows[0]['id']);
    }
}

<?php

namespace Tests\Feature;

use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\RestaurantProvisioningService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

/**
 * Every way a user account can come into existence, crossed with every role.
 *
 * There are exactly three creation paths, and each mints one kind of account:
 *
 *   POST /api/admin/users        → platform staff (ADMIN|MODERATOR|SALES|SUPPORT)
 *   POST /api/admin/restaurants  → a tenant plus its RESTAURANT_ADMIN owner
 *   POST /api/dashboard/staff    → RESTAURANT_STAFF inside the actor's tenant
 *
 * SUPER_ADMIN is deliberately mintable by none of them. The cases below assert
 * both halves of each boundary: that the allowed combinations work, and that
 * the disallowed ones are refused rather than silently downgraded.
 */
class UserCreationMatrixTest extends TestCase
{
    use RefreshDatabase;

    // ---------------------------------------------------------------- helpers

    private function platformUser(RoleEnum $role): User
    {
        return User::factory()->create([
            'role' => $role,
            'restaurant_id' => null,
            'status' => UserStatus::ACTIVE,
        ]);
    }

    /** @param  list<TenantCapability>  $capabilities */
    private function role(Restaurant $restaurant, string $name, array $capabilities): Role
    {
        $role = new Role(['name' => $name]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand(array_map(fn ($c) => $c->value, $capabilities)),
        ])->save();

        return $role;
    }

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'New Person',
            'username' => 'new.person',
            'email' => 'new.person@example.test',
        ], $overrides);
    }

    // ============================================================== PLATFORM ==

    public static function assignablePlatformRoles(): array
    {
        return [
            'ADMIN' => ['ADMIN'],
            'MODERATOR' => ['MODERATOR'],
            'SALES' => ['SALES'],
            'SUPPORT' => ['SUPPORT'],
        ];
    }

    #[DataProvider('assignablePlatformRoles')]
    public function test_super_admin_can_create_each_assignable_platform_role(string $role): void
    {
        $this->actingAs($this->platformUser(RoleEnum::SUPER_ADMIN))
            ->postJson('/api/admin/users', $this->payload([
                'username' => strtolower($role).'.user',
                'email' => strtolower($role).'@example.test',
                'role' => $role,
            ]))
            ->assertCreated();

        $created = User::where('username', strtolower($role).'.user')->first();

        $this->assertNotNull($created);
        $this->assertSame($role, $created->role->value);
        // A platform account belongs to no tenant, whatever the caller sent.
        $this->assertNull($created->restaurant_id);
        $this->assertNull($created->role_id);
    }

    public static function unassignableRoles(): array
    {
        return [
            'SUPER_ADMIN cannot be minted' => ['SUPER_ADMIN'],
            'RESTAURANT_ADMIN comes with a restaurant' => ['RESTAURANT_ADMIN'],
            'RESTAURANT_STAFF belongs to a tenant' => ['RESTAURANT_STAFF'],
            'a role that does not exist' => ['WIZARD'],
        ];
    }

    #[DataProvider('unassignableRoles')]
    public function test_platform_endpoint_refuses_roles_outside_its_remit(string $role): void
    {
        $this->actingAs($this->platformUser(RoleEnum::SUPER_ADMIN))
            ->postJson('/api/admin/users', $this->payload(['role' => $role]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('role');

        $this->assertDatabaseMissing('users', ['username' => 'new.person']);
    }

    public static function nonSuperPlatformRoles(): array
    {
        return [
            'ADMIN' => ['ADMIN'],
            'MODERATOR' => ['MODERATOR'],
            'SALES' => ['SALES'],
            'SUPPORT' => ['SUPPORT'],
        ];
    }

    /** platform_users.manage belongs to SUPER_ADMIN alone — even ADMIN cannot mint colleagues. */
    #[DataProvider('nonSuperPlatformRoles')]
    public function test_other_platform_staff_cannot_create_platform_users(string $role): void
    {
        $this->actingAs($this->platformUser(RoleEnum::from($role)))
            ->postJson('/api/admin/users', $this->payload(['role' => 'SUPPORT']))
            ->assertForbidden();

        $this->assertDatabaseMissing('users', ['username' => 'new.person']);
    }

    public function test_tenant_accounts_cannot_reach_the_platform_endpoint(): void
    {
        $restaurant = Restaurant::factory()->create();

        foreach ([
            User::factory()->restaurantAdmin($restaurant->id)->create(),
            User::factory()->staff($restaurant->id, $this->role($restaurant, 'Any', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE])->id)->create(),
        ] as $actor) {
            $this->actingAs($actor)
                ->postJson('/api/admin/users', $this->payload(['role' => 'SUPPORT']))
                ->assertForbidden();
        }
    }

    public function test_the_platform_endpoint_is_closed_to_anonymous_callers(): void
    {
        $this->postJson('/api/admin/users', $this->payload(['role' => 'SUPPORT']))
            ->assertUnauthorized();
    }

    public function test_platform_usernames_and_emails_must_be_unique(): void
    {
        $super = $this->platformUser(RoleEnum::SUPER_ADMIN);
        $this->actingAs($super);

        $this->postJson('/api/admin/users', $this->payload(['role' => 'SUPPORT']))->assertCreated();

        $this->postJson('/api/admin/users', $this->payload([
            'role' => 'SUPPORT', 'email' => 'other@example.test',
        ]))->assertStatus(422)->assertJsonValidationErrors('username');

        $this->postJson('/api/admin/users', $this->payload([
            'role' => 'SUPPORT', 'username' => 'other.person',
        ]))->assertStatus(422)->assertJsonValidationErrors('email');
    }

    /** A tenant's staff may hold the same username — those are scoped per restaurant. */
    public function test_a_platform_username_does_not_collide_with_tenant_staff(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Admin', TenantCapability::cases());
        User::factory()->staff($restaurant->id, $role->id)->create(['username' => 'new.person', 'email' => null]);

        $this->actingAs($this->platformUser(RoleEnum::SUPER_ADMIN))
            ->postJson('/api/admin/users', $this->payload(['role' => 'SUPPORT']))
            ->assertCreated();
    }

    // ================================================================ OWNER ==

    public function test_provisioning_a_restaurant_creates_its_owner_and_admin_role(): void
    {
        ['restaurant' => $restaurant, 'admin' => $owner] = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'Provisioned', 'slug' => 'provisioned'],
            ['name' => 'Owner', 'username' => 'owner', 'email' => 'owner@example.test'],
        );

        $this->assertSame(RoleEnum::RESTAURANT_ADMIN, $owner->role);
        $this->assertSame($restaurant->id, $owner->restaurant_id);
        // The owner's power is implicit, not granted through a Role row.
        $this->assertNull($owner->role_id);
        $this->assertTrue($owner->holdsTenantCapability(TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE));

        $this->assertSame(
            ['admin'],
            Role::where('restaurant_id', $restaurant->id)->pluck('slug')->all(),
        );
    }

    public static function rolesThatMayProvision(): array
    {
        // restaurants.manage is what the provisioning route is gated on.
        return ['SUPER_ADMIN' => ['SUPER_ADMIN', true], 'ADMIN' => ['ADMIN', true],
            'MODERATOR' => ['MODERATOR', true], 'SALES' => ['SALES', false], 'SUPPORT' => ['SUPPORT', false]];
    }

    #[DataProvider('rolesThatMayProvision')]
    public function test_only_platform_roles_with_restaurants_manage_can_provision_an_owner(string $role, bool $allowed): void
    {
        // Slugs allow only lowercase letters, digits and hyphens.
        $slug = 'prov-'.str_replace('_', '-', strtolower($role));
        $username = 'owner-'.strtolower($role);

        $response = $this->actingAs($this->platformUser(RoleEnum::from($role)))
            ->postJson('/api/admin/restaurants', [
                'name_en' => 'Provisioned',
                'slug' => $slug,
                'default_language' => 'en',
                'currency' => 'EGP',
                'admin' => [
                    'name' => 'Owner',
                    'username' => $username,
                    'email' => strtolower($role).'.owner@example.test',
                ],
            ]);

        if (! $allowed) {
            $response->assertForbidden();
            $this->assertDatabaseMissing('users', ['username' => $username]);

            return;
        }

        // A permitted role must actually create the pair, not merely pass the
        // gate — an accepted-but-invalid payload would hide a broken path.
        $response->assertCreated();

        $owner = User::where('username', $username)->first();
        $this->assertNotNull($owner);
        $this->assertSame(RoleEnum::RESTAURANT_ADMIN, $owner->role);
        $this->assertSame(
            Restaurant::where('slug', $slug)->value('id'),
            $owner->restaurant_id,
        );
    }

    // ================================================================ STAFF ==

    public function test_owner_can_create_staff_on_the_full_access_admin_role(): void
    {
        ['restaurant' => $restaurant] = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'Staffed', 'slug' => 'staffed'],
            ['name' => 'Owner', 'username' => 'owner', 'email' => 'owner@example.test'],
        );
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $admin = Role::where('restaurant_id', $restaurant->id)->where('slug', 'admin')->first();

        $this->actingAs($owner)
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $admin->id]))
            ->assertCreated();

        $created = User::where('username', 'new.person')->first();

        $this->assertSame(RoleEnum::RESTAURANT_STAFF, $created->role);
        $this->assertSame($restaurant->id, $created->restaurant_id);
        $this->assertSame($admin->id, $created->role_id);
        $this->assertTrue($created->holdsTenantCapability(TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE));
    }

    public function test_owner_can_create_staff_on_a_narrow_custom_role(): void
    {
        $restaurant = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $waiter = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);

        $this->actingAs($owner)
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $waiter->id]))
            ->assertCreated();

        $created = User::where('username', 'new.person')->first();

        $this->assertTrue($created->holdsTenantCapability(TenantCapability::ORDERS_UPDATE));
        $this->assertFalse($created->holdsTenantCapability(TenantCapability::SETTINGS_UPDATE));
    }

    /** The escalation boundary: staff.manage is not a licence to mint someone stronger. */
    public function test_staff_cannot_create_an_account_more_powerful_than_themselves(): void
    {
        $restaurant = Restaurant::factory()->create();
        $limited = $this->role($restaurant, 'Supervisor', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE, TenantCapability::ORDERS_UPDATE]);
        $powerful = $this->role($restaurant, 'Everything', TenantCapability::cases());

        $actor = User::factory()->staff($restaurant->id, $limited->id)->create();

        $this->actingAs($actor)
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $powerful->id]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('role_id');

        $this->assertDatabaseMissing('users', ['username' => 'new.person']);
    }

    public function test_staff_may_create_an_account_at_or_below_their_own_level(): void
    {
        $restaurant = Restaurant::factory()->create();
        $supervisor = $this->role($restaurant, 'Supervisor', [TenantCapability::STAFF_CREATE, TenantCapability::STAFF_UPDATE, TenantCapability::STAFF_DELETE, TenantCapability::ORDERS_UPDATE]);
        $narrower = $this->role($restaurant, 'Runner', [TenantCapability::ORDERS_VIEW]);

        $this->actingAs(User::factory()->staff($restaurant->id, $supervisor->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $narrower->id]))
            ->assertCreated();
    }

    public function test_staff_without_staff_manage_cannot_create_anyone(): void
    {
        $restaurant = Restaurant::factory()->create();
        $waiter = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);
        $target = $this->role($restaurant, 'Other', [TenantCapability::ORDERS_VIEW]);

        $this->actingAs(User::factory()->staff($restaurant->id, $waiter->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $target->id]))
            ->assertForbidden();
    }

    public function test_a_role_from_another_tenant_cannot_be_assigned(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();
        $theirRole = $this->role($theirs, 'Their Admin', TenantCapability::cases());

        $this->actingAs(User::factory()->restaurantAdmin($mine->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $theirRole->id]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('role_id');

        $this->assertDatabaseMissing('users', ['username' => 'new.person']);
    }

    public function test_usernames_are_unique_within_a_tenant_but_reusable_across_tenants(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();
        $roleA = $this->role($a, 'Admin', TenantCapability::cases());
        $roleB = $this->role($b, 'Admin', TenantCapability::cases());

        $this->actingAs(User::factory()->restaurantAdmin($a->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $roleA->id]))
            ->assertCreated();

        // Same username again in the same tenant → rejected.
        $this->actingAs(User::factory()->restaurantAdmin($a->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload([
                'role_id' => $roleA->id, 'email' => 'second@example.test',
            ]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('username');

        // The same username in a different tenant is a different person.
        $this->actingAs(User::factory()->restaurantAdmin($b->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload([
                'role_id' => $roleB->id, 'email' => 'other.tenant@example.test',
            ]))
            ->assertCreated();
    }

    /** Email is globally unique — the column is nullable but shared across portals. */
    public function test_an_email_already_used_anywhere_is_rejected(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Admin', TenantCapability::cases());
        $this->platformUser(RoleEnum::SUPPORT)->forceFill(['email' => 'taken@example.test'])->save();

        $this->actingAs(User::factory()->restaurantAdmin($restaurant->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload([
                'role_id' => $role->id, 'email' => 'taken@example.test',
            ]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('email');
    }

    /** Floor staff log in with a username alone; the generated password is returned once. */
    public function test_staff_can_be_created_without_an_email_and_with_a_generated_password(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Waiter', [TenantCapability::ORDERS_UPDATE]);

        $response = $this->actingAs(User::factory()->restaurantAdmin($restaurant->id)->create())
            ->postJson('/api/dashboard/staff', [
                'name' => 'Floor Staff', 'username' => 'floor1', 'role_id' => $role->id,
            ])
            ->assertCreated();

        $this->assertNotEmpty($response->json('generated_password'));
        $created = User::where('username', 'floor1')->first();
        $this->assertNull($created->email);
        $this->assertTrue(Hash::check(
            $response->json('generated_password'),
            $created->password,
        ));
    }

    public function test_platform_staff_cannot_reach_the_tenant_staff_endpoint(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Admin', TenantCapability::cases());

        foreach (['SUPER_ADMIN', 'ADMIN', 'SUPPORT'] as $platformRole) {
            $this->actingAs($this->platformUser(RoleEnum::from($platformRole)))
                ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $role->id]))
                ->assertForbidden();
        }
    }

    public function test_a_suspended_account_cannot_create_anyone(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Admin', TenantCapability::cases());
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create(['status' => UserStatus::SUSPENDED]);

        $this->actingAs($owner)
            ->postJson('/api/dashboard/staff', $this->payload(['role_id' => $role->id]))
            ->assertForbidden();
    }

    /** The tenant endpoint mints staff and only staff — role is pinned, not taken from input. */
    public function test_the_tenant_endpoint_cannot_be_talked_into_minting_an_owner(): void
    {
        $restaurant = Restaurant::factory()->create();
        $role = $this->role($restaurant, 'Admin', TenantCapability::cases());

        $this->actingAs(User::factory()->restaurantAdmin($restaurant->id)->create())
            ->postJson('/api/dashboard/staff', $this->payload([
                'role_id' => $role->id,
                'role' => 'RESTAURANT_ADMIN',
                'restaurant_id' => Restaurant::factory()->create()->id,
            ]))
            ->assertCreated();

        $created = User::where('username', 'new.person')->first();

        $this->assertSame(RoleEnum::RESTAURANT_STAFF, $created->role);
        $this->assertSame($restaurant->id, $created->restaurant_id);
    }
}

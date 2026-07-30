<?php

namespace Tests\Feature\Admin;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class PlatformUserTest extends TestCase
{
    use RefreshDatabase;

    private function platformUser(RoleEnum $role): User
    {
        return User::factory()->create(['role' => $role, 'restaurant_id' => null]);
    }

    public function test_super_admin_can_create_a_platform_user(): void
    {
        Notification::fake();
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/users', [
            'name' => 'Sam Sales',
            'username' => 'sam.sales',
            'email' => 'sam@example.com',
            'role' => RoleEnum::SALES->value,
        ])->assertCreated()
            ->assertJsonPath('data.role', 'SALES')
            ->assertJsonPath('data.restaurant_id', null)
            ->assertJsonPath('generated_password', fn ($pw) => is_string($pw) && strlen($pw) >= 12);

        $this->assertDatabaseHas('users', [
            'username' => 'sam.sales',
            'role' => 'SALES',
            'restaurant_id' => null,
        ]);
    }

    public function test_created_user_can_log_in_with_supplied_password(): void
    {
        Notification::fake();
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/users', [
            'name' => 'Dana Support',
            'username' => 'dana.support',
            'email' => 'dana@example.com',
            'role' => RoleEnum::SUPPORT->value,
            'password' => 'secret-pass-123',
        ])->assertCreated();

        $this->postJson('/api/auth/login', [
            'username' => 'dana.support',
            'password' => 'secret-pass-123',
        ])->assertOk()->assertJsonPath('data.role', 'SUPPORT');
    }

    public function test_super_admin_and_restaurant_admin_roles_are_not_assignable(): void
    {
        $sa = User::factory()->superAdmin()->create();

        foreach ([RoleEnum::SUPER_ADMIN->value, RoleEnum::RESTAURANT_ADMIN->value] as $role) {
            $this->actingAs($sa)->postJson('/api/admin/users', [
                'name' => 'Nope',
                'username' => 'nope'.strtolower($role),
                'email' => 'nope'.strtolower($role).'@example.com',
                'role' => $role,
            ])->assertUnprocessable()->assertJsonValidationErrors('role');
        }
    }

    public function test_index_lists_only_platform_users_not_restaurant_admins(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $this->platformUser(RoleEnum::SALES);
        $r = Restaurant::factory()->create();
        User::factory()->restaurantAdmin($r->id)->create();

        $res = $this->actingAs($sa)->getJson('/api/admin/users')->assertOk();

        foreach ($res->json('data') as $row) {
            $this->assertNull($row['restaurant_id']);
            $this->assertNotSame('RESTAURANT_ADMIN', $row['role']);
        }
    }

    public function test_sales_can_manage_leads_and_plans_but_not_write_restaurants(): void
    {
        $sales = $this->platformUser(RoleEnum::SALES);

        // Granted: leads + plans (422 = validation, i.e. the gate let it through).
        $this->actingAs($sales)->getJson('/api/admin/leads')->assertOk();
        $this->actingAs($sales)->postJson('/api/admin/plans', [])->assertUnprocessable();
        // Denied: restaurants are read-only for Sales, and audit is off-limits.
        $this->actingAs($sales)->postJson('/api/admin/restaurants', [])->assertForbidden();
        $this->actingAs($sales)->getJson('/api/admin/audit-logs')->assertForbidden();
        // But reading the restaurant list is allowed.
        $this->actingAs($sales)->getJson('/api/admin/restaurants')->assertOk();
    }

    public function test_moderator_can_manage_restaurants_but_not_plans(): void
    {
        $mod = $this->platformUser(RoleEnum::MODERATOR);

        // 422 (validation), not 403 → the capability gate let it through.
        $this->actingAs($mod)->postJson('/api/admin/restaurants', [])->assertUnprocessable();
        $this->actingAs($mod)->postJson('/api/admin/plans', [])->assertForbidden();
    }

    public function test_only_super_admin_can_manage_platform_users(): void
    {
        foreach ([RoleEnum::ADMIN, RoleEnum::MODERATOR, RoleEnum::SALES, RoleEnum::SUPPORT] as $role) {
            $user = $this->platformUser($role);
            $this->actingAs($user)->getJson('/api/admin/users')->assertForbidden();
        }
    }

    public function test_restaurant_admin_cannot_reach_the_admin_panel(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/admin/users')->assertForbidden();
        $this->actingAs($admin)->getJson('/api/admin/restaurants')->assertForbidden();
    }

    public function test_cannot_delete_or_mutate_a_super_admin_account(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $other = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->deleteJson("/api/admin/users/{$other->id}")->assertForbidden();
        $this->assertDatabaseHas('users', ['id' => $other->id]);
    }

    public function test_restaurant_user_is_invisible_to_update(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($sa)->putJson("/api/admin/users/{$admin->id}", [
            'name' => 'Hijack',
            'username' => 'hijack',
            'email' => 'hijack@example.com',
            'role' => RoleEnum::ADMIN->value,
        ])->assertNotFound();
    }

    public function test_super_admin_can_update_and_delete_a_platform_user(): void
    {
        Notification::fake();
        $sa = User::factory()->superAdmin()->create();
        $user = $this->platformUser(RoleEnum::SUPPORT);

        $this->actingAs($sa)->putJson("/api/admin/users/{$user->id}", [
            'name' => 'Promoted',
            'username' => 'promoted',
            'email' => 'promoted@example.com',
            'role' => RoleEnum::MODERATOR->value,
            'status' => UserStatus::ACTIVE->value,
        ])->assertOk()->assertJsonPath('data.role', 'MODERATOR');

        $this->actingAs($sa)->deleteJson("/api/admin/users/{$user->id}")->assertOk();
        $this->assertDatabaseMissing('users', ['id' => $user->id]);
    }
}

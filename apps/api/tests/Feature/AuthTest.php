<?php

namespace Tests\Feature;

use App\Enums\UserStatus;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_log_in(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'password'])
            ->assertOk()
            ->assertJsonPath('data.role', 'SUPER_ADMIN');
    }

    public function test_login_is_case_insensitive_for_username(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        $this->postJson('/api/auth/login', ['username' => 'SuperAdmin', 'password' => 'password'])
            ->assertOk()
            ->assertJsonPath('data.username', 'superadmin');
    }

    public function test_login_fails_with_wrong_password(): void
    {
        User::factory()->superAdmin()->create(['username' => 'superadmin']);

        // Wrong credentials are an authentication failure → 401.
        $this->postJson('/api/auth/login', ['username' => 'superadmin', 'password' => 'nope'])
            ->assertStatus(401);
    }

    public function test_suspended_user_cannot_log_in(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'susp']);
        User::factory()->restaurantAdmin($r->id)->create([
            'username' => 'suspendedadmin',
            'status' => UserStatus::SUSPENDED,
        ]);

        // On the account's own subdomain, so the attempt reaches the status check.
        // A known-but-not-allowed account → 403 (distinct from wrong-credentials 401).
        $this->postJson('http://susp.example.com/api/auth/login', ['username' => 'suspendedadmin', 'password' => 'password'])
            ->assertStatus(403);
    }

    public function test_me_returns_restaurant_context_for_restaurant_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/auth/me')
            ->assertOk()
            ->assertJsonPath('data.role', 'RESTAURANT_ADMIN')
            ->assertJsonPath('data.restaurant.slug', $r->slug);
    }
}

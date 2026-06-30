<?php

namespace Tests\Feature;

use App\Enums\RoleEnum;
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
        $admin = User::factory()->superAdmin()->create(['email' => 'sa@test.com']);

        $this->postJson('/api/auth/login', ['email' => 'sa@test.com', 'password' => 'password'])
            ->assertOk()
            ->assertJsonPath('data.role', 'SUPER_ADMIN');
    }

    public function test_login_fails_with_wrong_password(): void
    {
        User::factory()->superAdmin()->create(['email' => 'sa@test.com']);

        $this->postJson('/api/auth/login', ['email' => 'sa@test.com', 'password' => 'nope'])
            ->assertStatus(422);
    }

    public function test_suspended_user_cannot_log_in(): void
    {
        $r = Restaurant::factory()->create();
        User::factory()->restaurantAdmin($r->id)->create([
            'email' => 'ra@test.com',
            'status' => UserStatus::SUSPENDED,
        ]);

        $this->postJson('/api/auth/login', ['email' => 'ra@test.com', 'password' => 'password'])
            ->assertStatus(422);
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

<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

class ChangePasswordTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_user_can_change_password_and_keep_a_working_session(): void
    {
        $r = Restaurant::factory()->create();
        User::factory()->restaurantAdmin($r->id)->create(['username' => 'owner']);

        // Real login to obtain a token (factory password is 'password').
        $token = $this->postJson('/api/auth/login', [
            'username' => 'owner', 'password' => 'password', 'restaurant' => $r->slug,
        ])->assertOk()->json('token');

        $newToken = $this->withToken($token)->postJson('/api/auth/change-password', [
            'current_password' => 'password',
            'password' => 'NewSecret12345',
            'password_confirmation' => 'NewSecret12345',
        ])->assertOk()->json('token');

        // A fresh token is returned so the current device stays signed in.
        $this->assertNotEmpty($newToken);
        $this->withToken($newToken)->getJson('/api/auth/me')->assertOk();

        // The new password is actually persisted.
        $this->assertTrue(Hash::check('NewSecret12345', User::where('username', 'owner')->first()->password));
    }

    public function test_wrong_current_password_is_rejected(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->postJson('/api/auth/change-password', [
            'current_password' => 'not-the-password',
            'password' => 'NewSecret12345',
            'password_confirmation' => 'NewSecret12345',
        ])->assertUnprocessable()->assertJsonValidationErrors('current_password');
    }

    public function test_weak_new_password_is_rejected(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->postJson('/api/auth/change-password', [
            'current_password' => 'password',
            'password' => 'weak',
            'password_confirmation' => 'weak',
        ])->assertUnprocessable()->assertJsonValidationErrors('password');
    }

    public function test_new_password_must_differ_from_current(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->postJson('/api/auth/change-password', [
            'current_password' => 'password',
            'password' => 'password',
            'password_confirmation' => 'password',
        ])->assertUnprocessable()->assertJsonValidationErrors('password');
    }

    public function test_platform_user_can_also_change_their_password(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/auth/change-password', [
            'current_password' => 'password',
            'password' => 'NewSecret12345',
            'password_confirmation' => 'NewSecret12345',
        ])->assertOk();
    }

    public function test_change_password_requires_authentication(): void
    {
        $this->postJson('/api/auth/change-password', [
            'current_password' => 'password',
            'password' => 'NewSecret12345',
            'password_confirmation' => 'NewSecret12345',
        ])->assertUnauthorized();
    }
}

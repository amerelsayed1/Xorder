<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantAdminUpdateTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_update_admin_identity(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/admin", [
            'name' => 'New Owner',
            'username' => 'new.owner',
            'email' => 'new.owner@example.com',
        ])->assertOk()
            ->assertJsonPath('data.name', 'New Owner')
            ->assertJsonPath('data.username', 'new.owner');

        $admin->refresh();
        $this->assertSame('New Owner', $admin->name);
        $this->assertSame('new.owner', $admin->username);
        $this->assertSame('new.owner@example.com', $admin->email);
    }

    public function test_keeping_the_same_username_and_email_is_allowed(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create([
            'username' => 'keeper',
            'email' => 'keeper@example.com',
        ]);

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/admin", [
            'name' => 'Renamed',
            'username' => 'keeper',
            'email' => 'keeper@example.com',
        ])->assertOk();

        $this->assertSame('Renamed', $admin->fresh()->name);
    }

    public function test_email_must_be_unique_across_users(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();
        User::factory()->restaurantAdmin($r->id)->create();
        $other = User::factory()->create(['email' => 'taken@example.com']);

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/admin", [
            'name' => 'X',
            'username' => 'x.user',
            'email' => 'taken@example.com',
        ])->assertUnprocessable()
            ->assertJsonValidationErrors('email');
    }

    public function test_non_super_admin_is_forbidden(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->patchJson("/api/admin/restaurants/{$r->id}/admin", [
            'name' => 'Hacker',
            'username' => 'hacker',
        ])->assertForbidden();
    }
}

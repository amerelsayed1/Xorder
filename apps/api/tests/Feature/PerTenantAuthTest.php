<?php

namespace Tests\Feature;

use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Usernames are unique per tenant and login is scoped to the subdomain the
 * request arrives on, so an account can only sign in on its own restaurant.
 */
class PerTenantAuthTest extends TestCase
{
    use RefreshDatabase;

    public function test_two_restaurants_can_share_a_username(): void
    {
        $a = Restaurant::factory()->create();
        $b = Restaurant::factory()->create();

        User::factory()->restaurantAdmin($a->id)->create(['username' => 'manager']);
        User::factory()->restaurantAdmin($b->id)->create(['username' => 'manager']);

        $this->assertSame(2, User::where('username', 'manager')->count());
    }

    public function test_login_is_scoped_to_the_subdomain(): void
    {
        $a = Restaurant::factory()->create(['slug' => 'alpha']);
        $b = Restaurant::factory()->create(['slug' => 'beta']);
        $adminA = User::factory()->restaurantAdmin($a->id)->create(['username' => 'manager', 'password' => 'passA']);
        User::factory()->restaurantAdmin($b->id)->create(['username' => 'manager', 'password' => 'passB']);

        // Correct subdomain + that tenant's password → that tenant's admin.
        $this->postJson('http://alpha.example.com/api/auth/login', ['username' => 'manager', 'password' => 'passA'])
            ->assertOk()
            ->assertJsonPath('data.id', $adminA->id)
            ->assertJsonPath('data.restaurant.slug', 'alpha');

        // Same subdomain, but the OTHER tenant's password → rejected.
        $this->postJson('http://alpha.example.com/api/auth/login', ['username' => 'manager', 'password' => 'passB'])
            ->assertStatus(401);
    }

    public function test_account_cannot_log_in_on_another_subdomain(): void
    {
        $a = Restaurant::factory()->create(['slug' => 'alpha']);
        Restaurant::factory()->create(['slug' => 'beta']);
        User::factory()->restaurantAdmin($a->id)->create(['username' => 'owner', 'password' => 'secret']);

        $this->postJson('http://beta.example.com/api/auth/login', ['username' => 'owner', 'password' => 'secret'])
            ->assertStatus(401);
    }

    public function test_restaurant_admin_cannot_log_in_on_super_admin_host(): void
    {
        $a = Restaurant::factory()->create(['slug' => 'alpha']);
        User::factory()->restaurantAdmin($a->id)->create(['username' => 'owner', 'password' => 'secret']);

        $this->postJson('http://admin.example.com/api/auth/login', ['username' => 'owner', 'password' => 'secret'])
            ->assertStatus(401);
    }

    public function test_super_admin_logs_in_on_admin_host(): void
    {
        User::factory()->superAdmin()->create(['username' => 'root', 'password' => 'secret']);

        $this->postJson('http://admin.example.com/api/auth/login', ['username' => 'root', 'password' => 'secret'])
            ->assertOk()
            ->assertJsonPath('data.role', 'SUPER_ADMIN');
    }
}

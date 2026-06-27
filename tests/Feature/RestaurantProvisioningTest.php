<?php

namespace Tests\Feature;

use App\Enums\RoleEnum;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantProvisioningTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_creates_restaurant_with_first_admin(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/restaurants', [
            'name_en' => 'Tasty',
            'slug' => 'tasty',
            'default_language' => 'en',
            'admin' => ['name' => 'Owner', 'email' => 'owner@tasty.com'],
        ])->assertCreated()
            ->assertJsonPath('data.slug', 'tasty')
            ->assertJsonStructure(['generated_password']);

        $this->assertDatabaseHas('restaurants', ['slug' => 'tasty']);
        $admin = User::where('email', 'owner@tasty.com')->first();
        $this->assertSame(RoleEnum::RESTAURANT_ADMIN, $admin->role);
        $this->assertNotNull($admin->restaurant_id);
    }

    public function test_slug_must_be_unique(): void
    {
        $sa = User::factory()->superAdmin()->create();
        Restaurant::factory()->create(['slug' => 'taken']);

        $this->actingAs($sa)->postJson('/api/admin/restaurants', [
            'name_en' => 'X', 'slug' => 'taken', 'default_language' => 'en',
            'admin' => ['name' => 'O', 'email' => 'o@x.com'],
        ])->assertStatus(422)->assertJsonValidationErrors('slug');
    }

    public function test_slug_rejects_invalid_characters(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/restaurants', [
            'name_en' => 'X', 'slug' => 'Bad Slug!', 'default_language' => 'en',
            'admin' => ['name' => 'O', 'email' => 'o@x.com'],
        ])->assertStatus(422)->assertJsonValidationErrors('slug');
    }

    public function test_restaurant_admin_cannot_create_restaurants(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->postJson('/api/admin/restaurants', [
            'name_en' => 'X', 'slug' => 'x', 'default_language' => 'en',
            'admin' => ['name' => 'O', 'email' => 'o@x.com'],
        ])->assertForbidden();
    }
}

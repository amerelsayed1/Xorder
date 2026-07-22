<?php

namespace Tests\Feature;

use App\Enums\RoleEnum;
use App\Models\Category;
use App\Models\MenuItem;
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
            'currency' => 'EGP',
            'admin' => ['name' => 'Owner', 'username' => 'owner', 'email' => 'owner@tasty.com'],
        ])->assertCreated()
            ->assertJsonPath('data.slug', 'tasty')
            ->assertJsonStructure(['generated_password']);

        $this->assertDatabaseHas('restaurants', ['slug' => 'tasty']);
        $this->assertDatabaseHas('users', ['username' => 'owner', 'email' => 'owner@tasty.com']);
        $admin = User::where('username', 'owner')->first();
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

    public function test_super_admin_must_confirm_slug_before_deleting_restaurant(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->archived()->create(['slug' => 'delete-me']);

        $this->actingAs($sa)->deleteJson("/api/admin/restaurants/{$restaurant->id}", [
            'confirmation' => 'wrong-slug',
        ])->assertStatus(422)
            ->assertJsonValidationErrors('confirmation');

        $this->assertDatabaseHas('restaurants', ['id' => $restaurant->id]);
    }

    public function test_super_admin_must_archive_restaurant_before_permanent_delete(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->create(['slug' => 'delete-me']);

        $this->actingAs($sa)->deleteJson("/api/admin/restaurants/{$restaurant->id}", [
            'confirmation' => 'delete-me',
        ])->assertStatus(409)
            ->assertJsonPath('message', 'Archive the restaurant before deleting it permanently.');

        $this->assertDatabaseHas('restaurants', ['id' => $restaurant->id]);
    }

    public function test_super_admin_can_delete_restaurant_after_slug_confirmation(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $restaurant = Restaurant::factory()->archived()->create(['slug' => 'delete-me']);
        $admin = User::factory()->restaurantAdmin($restaurant->id)->create();
        $category = Category::factory()->create(['restaurant_id' => $restaurant->id]);
        $item = MenuItem::factory()->create([
            'restaurant_id' => $restaurant->id,
            'category_id' => $category->id,
        ]);

        $this->actingAs($sa)->deleteJson("/api/admin/restaurants/{$restaurant->id}", [
            'confirmation' => 'delete-me',
        ])->assertOk()
            ->assertJsonPath('message', 'Restaurant deleted.');

        $this->assertDatabaseMissing('restaurants', ['id' => $restaurant->id]);
        $this->assertDatabaseMissing('users', ['id' => $admin->id]);
        $this->assertDatabaseMissing('categories', ['id' => $category->id]);
        $this->assertDatabaseMissing('menu_items', ['id' => $item->id]);
    }
}

<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantSocialLinksTest extends TestCase
{
    use RefreshDatabase;

    private function admin(Restaurant $r): User
    {
        return User::factory()->restaurantAdmin($r->id)->create();
    }

    public function test_restaurant_admin_can_save_social_links(): void
    {
        $r = Restaurant::factory()->create();
        $admin = $this->admin($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'social_links' => [
                'instagram' => 'https://instagram.com/lazaza',
                'facebook' => 'https://facebook.com/lazaza',
                'tiktok' => '',
            ],
        ])->assertOk()
            ->assertJsonPath('data.social_links.instagram', 'https://instagram.com/lazaza');

        $this->assertSame('https://facebook.com/lazaza', $r->fresh()->social_links['facebook']);
    }

    public function test_invalid_social_url_is_rejected(): void
    {
        $r = Restaurant::factory()->create();
        $admin = $this->admin($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'social_links' => ['instagram' => 'not-a-url'],
        ])->assertStatus(422)->assertJsonValidationErrors('social_links.instagram');
    }

    public function test_public_menu_exposes_only_configured_social_links(): void
    {
        $r = Restaurant::factory()->create([
            'slug' => 'socials',
            'social_links' => ['instagram' => 'https://instagram.com/lazaza', 'facebook' => '', 'tiktok' => null],
        ]);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $res = $this->getJson('/api/public/restaurants/socials/menu')->assertOk();

        $res->assertJsonPath('data.restaurant.social_links.instagram', 'https://instagram.com/lazaza');
        // Empty / unset platforms are dropped, never sent as blank links.
        $this->assertArrayNotHasKey('facebook', $res->json('data.restaurant.social_links'));
        $this->assertArrayNotHasKey('tiktok', $res->json('data.restaurant.social_links'));
    }

    public function test_public_menu_social_links_default_to_empty_object(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'nosocials']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/nosocials/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.social_links', []);
    }
}

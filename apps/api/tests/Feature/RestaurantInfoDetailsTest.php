<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class RestaurantInfoDetailsTest extends TestCase
{
    use RefreshDatabase;

    private function admin(Restaurant $r): User
    {
        return User::factory()->restaurantAdmin($r->id)->create();
    }

    public function test_restaurant_admin_can_save_info_details(): void
    {
        $r = Restaurant::factory()->create();
        $admin = $this->admin($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'business_hours' => [
                'sat' => ['closed' => false, 'open' => '09:00', 'close' => '23:00'],
                'fri' => ['closed' => true, 'open' => '', 'close' => ''],
            ],
            'delivery_time_min' => 25,
            'delivery_time_max' => 35,
            'minimum_order' => '50.00',
            'latitude' => 30.0444,
            'longitude' => 31.2357,
        ])->assertOk()
            ->assertJsonPath('data.delivery_time_min', 25)
            ->assertJsonPath('data.business_hours.sat.open', '09:00');

        $fresh = $r->fresh();
        $this->assertSame(35, $fresh->delivery_time_max);
        $this->assertSame('50.00', $fresh->minimum_order);
        $this->assertTrue($fresh->business_hours['fri']['closed']);
    }

    public function test_delivery_max_below_min_is_rejected(): void
    {
        $r = Restaurant::factory()->create();
        $admin = $this->admin($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'delivery_time_min' => 40,
            'delivery_time_max' => 20,
        ])->assertStatus(422)->assertJsonValidationErrors('delivery_time_max');
    }

    public function test_latitude_requires_longitude(): void
    {
        $r = Restaurant::factory()->create();
        $admin = $this->admin($r);

        $this->actingAs($admin)->putJson('/api/dashboard/restaurant', [
            'latitude' => 30.0444,
        ])->assertStatus(422)->assertJsonValidationErrors('longitude');
    }

    public function test_public_menu_exposes_info_details(): void
    {
        $r = Restaurant::factory()->create([
            'slug' => 'infodemo',
            'timezone' => 'Africa/Cairo',
            'business_hours' => [
                'sat' => ['closed' => false, 'open' => '09:00', 'close' => '23:00'],
            ],
            'delivery_time_min' => 25,
            'delivery_time_max' => 35,
            'minimum_order' => '50.00',
            'latitude' => 30.0444,
            'longitude' => 31.2357,
        ]);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/infodemo/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.delivery_time_min', 25)
            ->assertJsonPath('data.restaurant.minimum_order', '50.00')
            ->assertJsonPath('data.restaurant.timezone', 'Africa/Cairo')
            ->assertJsonPath('data.restaurant.business_hours.sat.close', '23:00');
    }

    public function test_public_menu_business_hours_default_to_empty_object(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'nohours']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->getJson('/api/public/restaurants/nohours/menu')
            ->assertOk()
            ->assertJsonPath('data.restaurant.business_hours', []);
    }
}

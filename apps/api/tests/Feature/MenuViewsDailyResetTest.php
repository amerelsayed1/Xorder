<?php

namespace Tests\Feature;

use App\Enums\CurrencyEnum;
use App\Enums\RestaurantStatus;
use App\Models\MenuViewDaily;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\RestaurantProvisioningService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * "Views today" must reset at the restaurant's midnight, not the server's.
 *
 * The counter reported the server's calendar day while MenuViewDaily wrote its
 * rows against the restaurant's, so on a UTC server a Cairo owner (UTC+3) who
 * opened the dashboard just after midnight still saw the previous day's total —
 * it looked like the number never reset. These tests pin both halves to the
 * same clock.
 */
class MenuViewsDailyResetTest extends TestCase
{
    use RefreshDatabase;

    private function cairoRestaurant(): Restaurant
    {
        return Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE,
            'timezone' => 'Africa/Cairo',
        ]);
    }

    private function viewsToday(Restaurant $restaurant): int
    {
        $admin = User::factory()->restaurantAdmin($restaurant->id)->create();

        return $this->actingAs($admin)
            ->getJson('/api/dashboard/stats')
            ->assertOk()
            ->json('data.views_today');
    }

    public function test_views_reset_once_the_restaurants_own_midnight_passes(): void
    {
        $restaurant = $this->cairoRestaurant();

        // 23:30 in Cairo on the 24th — still the 24th everywhere that matters.
        Carbon::setTestNow(Carbon::parse('2026-08-24 20:30:00', 'UTC'));
        MenuViewDaily::record($restaurant->id);
        MenuViewDaily::record($restaurant->id);

        $this->assertSame(2, $this->viewsToday($restaurant));

        // 00:30 in Cairo on the 25th. The server is still on the 24th (21:30 UTC),
        // which is exactly the window the bug lived in.
        Carbon::setTestNow(Carbon::parse('2026-08-24 21:30:00', 'UTC'));

        $this->assertSame('2026-08-24', now()->toDateString(), 'precondition: server day has not turned over');
        $this->assertSame(0, $this->viewsToday($restaurant), 'the new local day must start from zero');

        // And the day just ended is still on record, not lost.
        $this->assertDatabaseHas('menu_view_dailies', [
            'restaurant_id' => $restaurant->id,
            'date' => '2026-08-24 00:00:00',
            'views' => 2,
        ]);
    }

    public function test_a_view_after_local_midnight_opens_the_new_day(): void
    {
        $restaurant = $this->cairoRestaurant();

        Carbon::setTestNow(Carbon::parse('2026-08-24 21:30:00', 'UTC')); // 00:30 Cairo, 25th
        MenuViewDaily::record($restaurant->id);

        $this->assertSame(1, $this->viewsToday($restaurant));
        $this->assertDatabaseHas('menu_view_dailies', [
            'restaurant_id' => $restaurant->id,
            'date' => '2026-08-25 00:00:00',
            'views' => 1,
        ]);
    }

    public function test_a_restaurant_without_a_timezone_falls_back_to_the_app_day(): void
    {
        $restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE,
            'timezone' => null,
        ]);

        Carbon::setTestNow(Carbon::parse('2026-08-24 21:30:00', 'UTC'));
        MenuViewDaily::record($restaurant->id);

        $this->assertSame(config('app.timezone', 'UTC'), $restaurant->localTimezone());
        $this->assertSame(1, $this->viewsToday($restaurant));
    }

    public function test_an_owner_can_change_the_timezone_and_the_counter_follows(): void
    {
        $restaurant = $this->cairoRestaurant();
        $admin = User::factory()->restaurantAdmin($restaurant->id)->create();

        Carbon::setTestNow(Carbon::parse('2026-08-24 21:30:00', 'UTC')); // 00:30 Cairo / 21:30 UTC
        MenuViewDaily::record($restaurant->id); // lands on the 25th, Cairo's day

        $this->actingAs($admin)
            ->putJson('/api/dashboard/restaurant', ['timezone' => 'UTC'])
            ->assertOk()
            ->assertJsonPath('data.timezone', 'UTC');

        // Same instant, different day boundary: on UTC it is still the 24th, so
        // the view recorded against the 25th is not part of "today".
        $this->assertSame(0, $this->viewsToday($restaurant->fresh()));
    }

    public function test_the_timezone_must_be_a_real_zone(): void
    {
        $restaurant = $this->cairoRestaurant();
        $admin = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->actingAs($admin)
            ->putJson('/api/dashboard/restaurant', ['timezone' => 'Mars/Olympus'])
            ->assertStatus(422)
            ->assertJsonValidationErrors('timezone');

        $this->assertSame('Africa/Cairo', $restaurant->fresh()->timezone);
    }

    public function test_a_new_restaurant_is_provisioned_with_a_timezone_matching_its_currency(): void
    {
        $provisioned = app(RestaurantProvisioningService::class)->provision(
            ['name_ar' => 'مطعم', 'name_en' => 'Cafe', 'slug' => 'tz-seed', 'currency' => CurrencyEnum::SAR->value],
            ['name' => 'Owner', 'email' => 'tz-seed@example.test'],
        );

        $restaurant = $provisioned['restaurant'];

        $this->assertSame('Asia/Riyadh', $restaurant->timezone);
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }
}

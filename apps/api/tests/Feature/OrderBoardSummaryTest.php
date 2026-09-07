<?php

namespace Tests\Feature;

use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * The orders board draws its tab counts and its day figures from the same
 * request that returns the rows. These pin the two rules that make those
 * numbers trustworthy: counts follow the search and the type filter but not the
 * status tabs, and "today" is the restaurant's day, not the server's.
 */
class OrderBoardSummaryTest extends TestCase
{
    use RefreshDatabase;

    private function seedBoard(Restaurant $r): void
    {
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true]);

        $make = fn (array $attrs) => Order::withoutGlobalScopes()->forceCreate(array_merge([
            'restaurant_id' => $r->id,
            'items' => [['name' => 'Burger', 'qty' => 1, 'line_total' => 50]],
            'total' => 50,
            'currency' => 'EGP',
            'source' => 'system',
        ], $attrs));

        $make(['status' => 'NEW', 'order_type' => 'delivery', 'customer_name' => 'Sara', 'customer_phone' => '+201111']);
        $make(['status' => 'NEW', 'order_type' => 'pickup', 'customer_name' => 'Faisal', 'customer_phone' => '+202222']);
        $make(['status' => 'COMPLETED', 'order_type' => 'delivery', 'customer_name' => 'Nora', 'total' => 120]);
        $make(['status' => 'CANCELLED', 'order_type' => 'dine_in', 'customer_name' => 'Hind']);
    }

    public function test_tab_counts_ignore_the_status_filter_but_follow_the_type_filter(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->seedBoard($r);

        // A selected status narrows the rows and leaves every count intact —
        // otherwise the tab you are standing on would report "4" and the rest 0.
        $this->actingAs($admin)->getJson('/api/dashboard/orders?status=NEW')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('summary.counts.all', 4)
            ->assertJsonPath('summary.counts.NEW', 2)
            ->assertJsonPath('summary.counts.COMPLETED', 1)
            ->assertJsonPath('summary.counts.CANCELLED', 1);

        // The type filter does narrow them, so a tab never promises rows that
        // clicking it would not show.
        $this->actingAs($admin)->getJson('/api/dashboard/orders?order_type=delivery')
            ->assertOk()
            ->assertJsonPath('summary.counts.all', 2)
            ->assertJsonPath('summary.counts.NEW', 1)
            ->assertJsonPath('summary.counts.COMPLETED', 1)
            ->assertJsonPath('summary.counts.CANCELLED', 0);
    }

    public function test_search_matches_customer_name_phone_and_either_half_of_the_code(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->seedBoard($r);
        $id = Order::withoutGlobalScopes()->where('customer_name', 'Nora')->value('id');

        $this->actingAs($admin)->getJson('/api/dashboard/orders?q=Sara')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.customer_name', 'Sara')
            ->assertJsonPath('summary.counts.all', 1);

        $this->actingAs($admin)->getJson('/api/dashboard/orders?q=202222')
            ->assertOk()
            ->assertJsonPath('data.0.customer_name', 'Faisal');

        // Staff read "ORD-12" off the screen; typing either form finds the row.
        $this->actingAs($admin)->getJson('/api/dashboard/orders?q=ORD-'.$id)
            ->assertOk()
            ->assertJsonPath('data.0.id', $id);
    }

    public function test_day_figures_turn_over_at_the_restaurants_midnight(): void
    {
        $r = Restaurant::factory()->create(['timezone' => 'Africa/Cairo']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // 21:30 UTC on the 24th is 00:30 on the 25th in Cairo: the restaurant's
        // day has turned over, the server's has not.
        Carbon::setTestNow(Carbon::parse('2026-08-24 21:30:00', 'UTC'));

        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true]);
        $make = fn (Carbon $at, string $status, float $total) => Order::withoutGlobalScopes()->forceCreate([
            'restaurant_id' => $r->id, 'items' => [], 'total' => $total, 'currency' => 'EGP',
            'source' => 'system', 'status' => $status, 'created_at' => $at, 'updated_at' => $at,
        ]);

        // Yesterday in Cairo (20:00 UTC on the 24th = 23:00 local on the 24th).
        $make(Carbon::parse('2026-08-24 20:00:00', 'UTC'), 'COMPLETED', 999);
        // Today in Cairo (21:00 UTC on the 24th = 00:00 local on the 25th).
        $make(Carbon::parse('2026-08-24 21:05:00', 'UTC'), 'COMPLETED', 120);
        $make(Carbon::parse('2026-08-24 21:10:00', 'UTC'), 'NEW', 50);

        $this->actingAs($admin)->getJson('/api/dashboard/orders')
            ->assertOk()
            ->assertJsonPath('summary.metrics.orders_today', 2)
            ->assertJsonPath('summary.metrics.completed_today', 1)
            ->assertJsonPath('summary.metrics.sales_today', '120.00')
            ->assertJsonPath('summary.metrics.new_orders', 1)
            ->assertJsonPath('summary.metrics.currency', 'EGP');

        Carbon::setTestNow();
    }
}

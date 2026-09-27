<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * Dashboard-home counters.
 *
 * The counters answer "what can a diner order right now?", so they have to
 * agree with what the public menu actually loads — which skips switched-off
 * categories entirely.
 */
class DashboardStatsTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private User $admin;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    private function category(bool $active): Category
    {
        return Category::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'is_active' => $active,
        ]);
    }

    private function item(Category $category, bool $available = true): MenuItem
    {
        return MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'is_available' => $available,
        ]);
    }

    private function stats(): array
    {
        return $this->actingAs($this->admin)
            ->getJson('/api/dashboard/stats')
            ->assertOk()
            ->json('data');
    }

    /** Place an order for the tenant at a given moment, with a given total. */
    private function orderAt(string $at, float $total, string $status = 'NEW'): Order
    {
        $order = new Order([
            'status' => $status,
            'items' => [['name' => 'Item', 'qty' => 1, 'line_total' => $total]],
            'total' => $total,
            'currency' => 'EGP',
            'order_type' => 'pickup',
            'source' => 'system',
        ]);
        $order->restaurant_id = $this->restaurant->id;
        $order->save();
        $order->forceFill(['created_at' => $at])->save();

        return $order;
    }

    public function test_sales_today_sums_todays_orders_and_counts_them(): void
    {
        $this->orderAt(now()->setTime(9, 0)->toDateTimeString(), 100.00);
        $this->orderAt(now()->setTime(13, 0)->toDateTimeString(), 40.50);
        $this->orderAt(now()->subDays(2)->setTime(13, 0)->toDateTimeString(), 999.00);

        $stats = $this->stats();

        $this->assertEquals(140.50, $stats['sales_today']);
        $this->assertSame(2, $stats['orders_today']);
    }

    public function test_a_cancelled_order_is_not_a_sale(): void
    {
        $this->orderAt(now()->setTime(9, 0)->toDateTimeString(), 100.00);
        $this->orderAt(now()->setTime(10, 0)->toDateTimeString(), 60.00, 'CANCELLED');

        $stats = $this->stats();

        $this->assertEquals(100.00, $stats['sales_today']);
        $this->assertSame(1, $stats['orders_today']);
    }

    public function test_sales_change_is_measured_against_yesterday(): void
    {
        $this->orderAt(now()->subDay()->setTime(12, 0)->toDateTimeString(), 100.00);
        $this->orderAt(now()->setTime(12, 0)->toDateTimeString(), 150.00);

        $this->assertSame(50, $this->stats()['sales_change_pct']);
    }

    /**
     * Going 0 -> something is not growth you can put a percentage on, so the
     * dashboard is handed null and shows nothing rather than "+100%".
     */
    public function test_sales_change_is_null_when_yesterday_had_no_sales(): void
    {
        $this->orderAt(now()->setTime(12, 0)->toDateTimeString(), 150.00);

        $this->assertNull($this->stats()['sales_change_pct']);
    }

    /**
     * The day boundary is the restaurant's, not the server's: an order placed
     * at 11pm Cairo time is still today's sale when the UTC clock has already
     * rolled over.
     */
    public function test_sales_today_uses_the_restaurants_own_day(): void
    {
        $this->restaurant->forceFill(['timezone' => 'Africa/Cairo'])->save();

        $localLateNight = Carbon::now('Africa/Cairo')->setTime(23, 30);
        $this->orderAt($localLateNight->copy()->utc()->toDateTimeString(), 75.00);

        $this->assertEquals(75.00, $this->stats()['sales_today']);
    }

    /** No till running means no shift panel — the common case for most tenants. */
    public function test_current_shift_is_null_without_an_open_shift(): void
    {
        $this->assertNull($this->stats()['current_shift']);
    }

    public function test_items_in_an_inactive_category_do_not_count_as_available(): void
    {
        $live = $this->category(true);
        $hidden = $this->category(false);

        $this->item($live);
        $this->item($live);
        $this->item($hidden);   // available flag on, but its category is off

        $stats = $this->stats();

        $this->assertSame(3, $stats['total_items'], 'the owner still has three items');
        $this->assertSame(2, $stats['available_items'], 'only the two a diner can reach');
        $this->assertSame(1, $stats['unavailable_items']);
    }

    public function test_an_unavailable_item_in_an_active_category_still_counts_as_unavailable(): void
    {
        $live = $this->category(true);
        $this->item($live);
        $this->item($live, available: false);

        $stats = $this->stats();

        $this->assertSame(2, $stats['total_items']);
        $this->assertSame(1, $stats['available_items']);
        $this->assertSame(1, $stats['unavailable_items']);
    }

    public function test_switching_a_category_off_moves_its_items_to_unavailable(): void
    {
        $category = $this->category(true);
        $this->item($category);
        $this->item($category);

        $this->assertSame(2, $this->stats()['available_items']);

        $category->update(['is_active' => false]);

        $after = $this->stats();
        $this->assertSame(0, $after['available_items']);
        $this->assertSame(2, $after['unavailable_items']);
        $this->assertSame(2, $after['total_items'], 'nothing was deleted, only hidden');
    }

    public function test_counters_never_reach_across_tenants(): void
    {
        $mine = $this->category(true);
        $this->item($mine);

        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $theirCategory = Category::factory()->create(['restaurant_id' => $other->id, 'is_active' => true]);
        MenuItem::factory()->count(4)->create([
            'restaurant_id' => $other->id,
            'category_id' => $theirCategory->id,
            'is_available' => true,
        ]);

        $stats = $this->stats();

        $this->assertSame(1, $stats['total_items']);
        $this->assertSame(1, $stats['available_items']);
    }
}

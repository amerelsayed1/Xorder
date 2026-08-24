<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\MenuViewDaily;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class InsightsTest extends TestCase
{
    use RefreshDatabase;

    /*
    |------------------------------------------------------------------
    | Super Admin platform insights
    |------------------------------------------------------------------
    */

    public function test_admin_insights_require_super_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/admin/insights')->assertForbidden();
    }

    public function test_admin_insights_are_unreachable_when_unauthenticated(): void
    {
        $this->getJson('/api/admin/insights')->assertUnauthorized();
    }

    public function test_admin_insights_aggregate_across_all_tenants(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        $a = Restaurant::factory()->create(['status' => 'ACTIVE']);
        $b = Restaurant::factory()->suspended()->create();
        Restaurant::factory()->create(); // empty restaurant, no categories/items

        $cat = Category::factory()->for($a)->create();
        MenuItem::factory()->count(3)->for($a)->for($cat)->create();
        MenuItem::factory()->for($b)->for(Category::factory()->for($b))->create();

        // Restaurant admins should be counted; super admin excluded.
        User::factory()->restaurantAdmin($a->id)->create();

        $this->actingAs($superAdmin)->getJson('/api/admin/insights')
            ->assertOk()
            ->assertJsonPath('data.restaurants.total', 3)
            ->assertJsonPath('data.restaurants.by_status.ACTIVE', 2) // a + empty default ACTIVE
            ->assertJsonPath('data.restaurants.by_status.SUSPENDED', 1)
            ->assertJsonPath('data.content.total_menu_items', 4)
            ->assertJsonPath('data.content.restaurant_admins', 1)
            ->assertJsonPath('data.needs_attention.restaurants_without_menu_items', 1)
            ->assertJsonStructure([
                'data' => [
                    'restaurants' => ['total', 'by_status', 'new_last_7_days', 'new_last_30_days'],
                    'subscriptions' => ['by_status', 'expiring_in_7_days', 'expiring_in_30_days', 'past_end_date'],
                    'content' => ['total_categories', 'total_menu_items', 'available_menu_items', 'restaurant_admins'],
                    'needs_attention',
                    'top_restaurants',
                    'recent_restaurants',
                ],
            ]);
    }

    public function test_admin_insights_flag_subscriptions_expiring_within_seven_days(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(3)->toDateString(),
        ]);
        Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(20)->toDateString(),
        ]);

        $this->actingAs($superAdmin)->getJson('/api/admin/insights')
            ->assertOk()
            ->assertJsonPath('data.subscriptions.expiring_in_7_days', 1)
            ->assertJsonPath('data.subscriptions.expiring_in_30_days', 2);
    }

    /*
    |------------------------------------------------------------------
    | Restaurant Admin menu-health insights
    |------------------------------------------------------------------
    */

    public function test_dashboard_insights_require_restaurant_admin(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        $this->actingAs($superAdmin)->getJson('/api/dashboard/insights')->assertForbidden();
    }

    public function test_dashboard_insights_are_tenant_scoped(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();

        $myCat = Category::factory()->for($mine)->create();
        MenuItem::factory()->count(2)->for($mine)->for($myCat)->create(['is_available' => true]);
        MenuItem::factory()->for($mine)->for($myCat)->unavailable()->create();

        // Another tenant's data must not leak into the totals.
        MenuItem::factory()->count(5)->for($theirs)->for(Category::factory()->for($theirs))->create();

        $admin = User::factory()->restaurantAdmin($mine->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()
            ->assertJsonPath('data.menu.total_items', 3)
            ->assertJsonPath('data.menu.available_items', 2)
            ->assertJsonPath('data.menu.unavailable_items', 1);
    }

    public function test_dashboard_insights_surface_empty_active_categories(): void
    {
        $r = Restaurant::factory()->create();
        $filled = Category::factory()->for($r)->create(['name_en' => 'Drinks']);
        MenuItem::factory()->for($r)->for($filled)->create();
        Category::factory()->for($r)->create(['name_en' => 'Desserts']); // active, no items

        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $response = $this->actingAs($admin)->getJson('/api/dashboard/insights')->assertOk();

        $issues = collect($response->json('data.needs_attention'));
        $empty = $issues->firstWhere('key', 'empty_active_categories');

        $this->assertNotNull($empty, 'Expected an empty_active_categories issue.');
        $this->assertSame(1, $empty['count']);
        $this->assertContains('Desserts', $empty['sample']);
    }

    public function test_dashboard_insights_report_subscription_days_remaining(): void
    {
        $r = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(10)->toDateString(),
        ]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()
            ->assertJsonPath('data.subscription.days_remaining', 10)
            ->assertJsonPath('data.subscription.writable', true);
    }

    /*
    |------------------------------------------------------------------
    | Orders per day, compared against the preceding fortnight
    |------------------------------------------------------------------
    */

    /** Place an order for $restaurant on a given day. */
    private function orderOn(Restaurant $restaurant, string $at): void
    {
        $order = new Order([
            'status' => 'NEW',
            'items' => [['name' => 'Item', 'qty' => 1, 'line_total' => 10]],
            'total' => 10,
            'currency' => 'EGP',
            'order_type' => 'pickup',
            'source' => 'system',
        ]);
        $order->restaurant_id = $restaurant->id;
        $order->save();
        $order->forceFill(['created_at' => $at])->save();
    }

    public function test_dashboard_insights_compare_orders_against_the_previous_fortnight(): void
    {
        $r = Restaurant::factory()->create();

        // Current window: 3 orders. Previous window: 2.
        $this->orderOn($r, now()->subDays(1)->toDateTimeString());
        $this->orderOn($r, now()->subDays(2)->toDateTimeString());
        $this->orderOn($r, now()->subDays(13)->toDateTimeString());
        $this->orderOn($r, now()->subDays(15)->toDateTimeString());
        $this->orderOn($r, now()->subDays(27)->toDateTimeString());
        // Older than both windows — must not be counted on either side.
        $this->orderOn($r, now()->subDays(40)->toDateTimeString());

        $data = $this->actingAs(User::factory()->restaurantAdmin($r->id)->create())
            ->getJson('/api/dashboard/insights')
            ->assertOk()
            ->json('data.engagement');

        $this->assertSame(3, $data['orders_14d']);
        $this->assertSame(2, $data['orders_14d_previous']);
        $this->assertEquals(50.0, $data['orders_change_pct']);

        // Both windows are dense and the same length, so the chart can lay one
        // over the other index-for-index.
        $this->assertCount(14, $data['daily']);
        $this->assertCount(14, $data['previous_daily']);
    }

    /** Growth from nothing is not a percentage — it is a first week. */
    public function test_change_percentage_is_null_when_the_previous_fortnight_was_empty(): void
    {
        $r = Restaurant::factory()->create();
        $this->orderOn($r, now()->subDays(1)->toDateTimeString());

        $data = $this->actingAs(User::factory()->restaurantAdmin($r->id)->create())
            ->getJson('/api/dashboard/insights')
            ->assertOk()
            ->json('data.engagement');

        $this->assertSame(1, $data['orders_14d']);
        $this->assertSame(0, $data['orders_14d_previous']);
        $this->assertNull($data['orders_change_pct']);
    }

    public function test_a_decline_is_reported_as_a_negative_change(): void
    {
        $r = Restaurant::factory()->create();
        $this->orderOn($r, now()->subDays(2)->toDateTimeString());
        $this->orderOn($r, now()->subDays(16)->toDateTimeString());
        $this->orderOn($r, now()->subDays(17)->toDateTimeString());
        $this->orderOn($r, now()->subDays(18)->toDateTimeString());
        $this->orderOn($r, now()->subDays(19)->toDateTimeString());

        $data = $this->actingAs(User::factory()->restaurantAdmin($r->id)->create())
            ->getJson('/api/dashboard/insights')
            ->assertOk()
            ->json('data.engagement');

        $this->assertEquals(-75.0, $data['orders_change_pct']);
    }

    /** Another tenant's orders must not appear on either side of the comparison. */
    public function test_the_comparison_is_tenant_scoped(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();

        $this->orderOn($mine, now()->subDays(1)->toDateTimeString());
        $this->orderOn($theirs, now()->subDays(1)->toDateTimeString());
        $this->orderOn($theirs, now()->subDays(20)->toDateTimeString());

        $data = $this->actingAs(User::factory()->restaurantAdmin($mine->id)->create())
            ->getJson('/api/dashboard/insights')
            ->assertOk()
            ->json('data.engagement');

        $this->assertSame(1, $data['orders_14d']);
        $this->assertSame(0, $data['orders_14d_previous']);
    }

    /*
    |------------------------------------------------------------------
    | Menu views bucket by the restaurant's day, not the server's
    |------------------------------------------------------------------
    */

    public function test_a_view_lands_on_the_restaurants_local_day_not_the_servers(): void
    {
        // 00:30 on the 24th in Cairo is still 22:30 on the 23rd in UTC. The
        // view belongs to the diner's day.
        Carbon::setTestNow('2026-08-23 22:30:00');

        $r = Restaurant::factory()->create(['slug' => 'cairo', 'timezone' => 'Africa/Cairo']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->withHeaders(['User-Agent' => 'Mozilla/5.0 (iPhone) Safari/604.1'])
            ->getJson('/api/public/restaurants/cairo/menu')
            ->assertOk();

        // Stored as a date column; compare the day, not the raw string.
        $this->assertSame('2026-08-24', MenuViewDaily::withoutGlobalScopes()
            ->where('restaurant_id', $r->id)->value('date')->toDateString());

        Carbon::setTestNow();
    }

    public function test_a_restaurant_without_a_timezone_falls_back_to_the_app_clock(): void
    {
        Carbon::setTestNow('2026-08-23 22:30:00');

        $r = Restaurant::factory()->create(['slug' => 'utcshop', 'timezone' => null]);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->withHeaders(['User-Agent' => 'Mozilla/5.0 (iPhone) Safari/604.1'])
            ->getJson('/api/public/restaurants/utcshop/menu')
            ->assertOk();

        $this->assertSame('2026-08-23', MenuViewDaily::withoutGlobalScopes()
            ->where('restaurant_id', $r->id)->value('date')->toDateString());

        Carbon::setTestNow();
    }

    public function test_repeat_views_on_the_same_local_day_increment_one_row(): void
    {
        Carbon::setTestNow('2026-08-24 01:00:00');

        $r = Restaurant::factory()->create(['slug' => 'busy', 'timezone' => 'Africa/Cairo']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        foreach (range(1, 3) as $i) {
            $this->withHeaders(['User-Agent' => 'Mozilla/5.0 (iPhone) Safari/604.1'])
                ->getJson('/api/public/restaurants/busy/menu')->assertOk();
        }

        $this->assertSame(1, MenuViewDaily::withoutGlobalScopes()->where('restaurant_id', $r->id)->count());
        $this->assertSame(3, (int) MenuViewDaily::withoutGlobalScopes()->where('restaurant_id', $r->id)->value('views'));

        Carbon::setTestNow();
    }

    /** Scripted clients and owner previews must never inflate the counter. */
    public function test_bots_and_previews_are_not_counted(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'clean']);
        $cat = Category::factory()->for($r)->create(['is_active' => true]);
        MenuItem::factory()->for($r)->for($cat)->create();

        $this->withHeaders(['User-Agent' => 'curl/8.7.1'])
            ->getJson('/api/public/restaurants/clean/menu')->assertOk();
        $this->withHeaders(['User-Agent' => 'Mozilla/5.0 (compatible; Googlebot/2.1)'])
            ->getJson('/api/public/restaurants/clean/menu')->assertOk();
        $this->withHeaders(['User-Agent' => 'Mozilla/5.0 (iPhone) Safari/604.1'])
            ->getJson('/api/public/restaurants/clean/menu?preview=1')->assertOk();

        $this->assertDatabaseCount('menu_view_dailies', 0);
    }
}

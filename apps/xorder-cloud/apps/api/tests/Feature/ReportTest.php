<?php

namespace Tests\Feature;

use App\Enums\OrderStatus;
use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class ReportTest extends TestCase
{
    use RefreshDatabase;

    private const TZ = 'Africa/Cairo';

    private Restaurant $restaurant;

    private User $admin;

    private Branch $branch;

    private DiningArea $indoor;

    private DiningArea $outdoor;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant = Restaurant::factory()->create([
            'status' => RestaurantStatus::ACTIVE,
            'slug' => 'reporty',
            'timezone' => self::TZ,
        ]);
        $this->admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $this->enableAnalytics();

        $this->branch = $this->makeBranch('Main');
        $this->indoor = $this->makeArea('Indoor', 'indoor');
        $this->outdoor = $this->makeArea('Outdoor', 'outdoor');
    }

    private function enableAnalytics(): void
    {
        $this->restaurant->features()->create(['feature_key' => 'product_analytics', 'is_enabled' => true]);
        $this->restaurant->load('features');
    }

    private function makeBranch(string $name): Branch
    {
        $b = new Branch(['name_en' => $name]);
        $b->restaurant_id = $this->restaurant->id;
        $b->save();

        return $b;
    }

    private function makeArea(string $name, string $type): DiningArea
    {
        $a = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => $name, 'type' => $type]);
        $a->restaurant_id = $this->restaurant->id;
        $a->save();

        return $a;
    }

    /**
     * @param  array<int,array<string,mixed>>  $items
     */
    private function makeOrder(DiningArea $area, string $localTime, array $items, float $total, string $status = 'NEW'): Order
    {
        $order = new Order([
            'branch_id' => $this->branch->id,
            'dining_area_id' => $area->id,
            'order_type' => 'dine_in',
            'status' => $status,
            'items' => $items,
            'total' => $total,
            'currency' => 'EGP',
        ]);
        $order->restaurant_id = $this->restaurant->id;
        // Orders persist created_at in UTC (app tz); store the UTC instant for
        // the given local wall-clock time so the service buckets it back into TZ.
        $order->created_at = Carbon::parse($localTime, self::TZ)->utc();
        $order->save();

        return $order;
    }

    private function seedOrders(): void
    {
        // Indoor breakfast orders.
        $this->makeOrder($this->indoor, '2026-07-15 09:00', [
            ['name' => 'Latte', 'qty' => 2, 'line_total' => 60],
            ['name' => 'Croissant', 'qty' => 1, 'line_total' => 30],
        ], 90);
        $this->makeOrder($this->indoor, '2026-07-15 10:30', [
            ['name' => 'Latte', 'qty' => 1, 'line_total' => 30],
        ], 30);
        // Outdoor dinner order.
        $this->makeOrder($this->outdoor, '2026-07-15 19:00', [
            ['name' => 'Burger', 'qty' => 3, 'line_total' => 300],
        ], 300);
        // Cancelled breakfast order — excluded by default.
        $this->makeOrder($this->indoor, '2026-07-15 09:15', [
            ['name' => 'Latte', 'qty' => 5, 'line_total' => 150],
        ], 150, OrderStatus::CANCELLED->value);
    }

    public function test_products_by_time_buckets_breakfast_and_sums_by_name(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time')
            ->assertOk();

        // Overall Latte quantity = 2 + 1 = 3 (cancelled 5 excluded), sales 90.
        $products = collect($res->json('data.products'))->keyBy('name');
        $this->assertSame(3, $products['Latte']['quantity']);
        $this->assertEquals(90.0, $products['Latte']['total_sales']);
        $this->assertSame('breakfast', $products['Latte']['most_active_period']);

        // The breakfast bucket carries both breakfast orders (not the dinner one).
        $breakfast = collect($res->json('data.periods'))->firstWhere('key', 'breakfast');
        $this->assertNotNull($breakfast);
        $this->assertSame(2, $breakfast['total_orders']);
        $latte = collect($breakfast['products'])->firstWhere('name', 'Latte');
        $this->assertSame(3, $latte['quantity']);

        // Burger sits in the dinner bucket.
        $dinner = collect($res->json('data.periods'))->firstWhere('key', 'dinner');
        $this->assertSame(1, $dinner['total_orders']);
    }

    public function test_cancelled_excluded_by_default_and_included_with_flag(): void
    {
        $this->seedOrders();

        $default = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time')->assertOk();
        $this->assertSame(3, collect($default->json('data.products'))->firstWhere('name', 'Latte')['quantity']);

        $withCancelled = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?include_cancelled=1')->assertOk();
        $this->assertSame(8, collect($withCancelled->json('data.products'))->firstWhere('name', 'Latte')['quantity']);
    }

    public function test_hourly_grouping_buckets_by_local_hour(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?group=hour')->assertOk();

        $this->assertSame('hour', $res->json('data.group'));
        $nineAm = collect($res->json('data.periods'))->firstWhere('key', '09:00');
        $this->assertNotNull($nineAm);
        $this->assertSame(1, $nineAm['total_orders']);
    }

    public function test_daily_grouping_buckets_by_local_date(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?group=day')->assertOk();

        $this->assertSame('day', $res->json('data.group'));

        // Every non-cancelled order shares the same local calendar day.
        $day = collect($res->json('data.periods'))->firstWhere('key', '2026-07-15');
        $this->assertNotNull($day);
        $this->assertSame(3, $day['total_orders']);

        // Latte's most-active bucket is now that date, not a day-part.
        $latte = collect($res->json('data.products'))->firstWhere('name', 'Latte');
        $this->assertSame('2026-07-15', $latte['most_active_period']);
    }

    public function test_time_window_filters_products_by_local_time(): void
    {
        $this->seedOrders();

        // 09:00–11:00 catches both breakfast orders (Latte) but not dinner.
        $morning = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?time_from=09:00&time_to=11:00')->assertOk();
        $products = collect($morning->json('data.products'))->keyBy('name');
        $this->assertSame(3, $products['Latte']['quantity']);
        $this->assertFalse($products->has('Burger'));

        // 18:00–20:00 catches only the dinner order.
        $evening = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?time_from=18:00&time_to=20:00')->assertOk();
        $eveningProducts = collect($evening->json('data.products'))->keyBy('name');
        $this->assertSame(3, $eveningProducts['Burger']['quantity']);
        $this->assertFalse($eveningProducts->has('Latte'));
    }

    public function test_time_window_wraps_past_midnight(): void
    {
        $this->seedOrders();
        // A 2 AM order — inside a 23:00→03:00 window that crosses midnight.
        $this->makeOrder($this->indoor, '2026-07-16 02:00', [
            ['name' => 'NightSnack', 'qty' => 1, 'line_total' => 40],
        ], 40);

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?time_from=23:00&time_to=03:00')->assertOk();

        $products = collect($res->json('data.products'))->keyBy('name');
        $this->assertSame(1, $products['NightSnack']['quantity']);
        $this->assertFalse($products->has('Latte'));   // 09:00 order excluded
    }

    public function test_day_of_week_filter_keeps_only_selected_weekdays(): void
    {
        // Seeded orders all fall on 2026-07-15 (a Wednesday, dayOfWeek=3).
        $this->seedOrders();
        // Add a Friday (2026-07-17, dayOfWeek=5) order with a distinct product.
        $this->makeOrder($this->indoor, '2026-07-17 13:00', [
            ['name' => 'FridayShawarma', 'qty' => 4, 'line_total' => 200],
        ], 200);

        // Friday only → just the Friday order.
        $friday = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?days_of_week[]=5')->assertOk();
        $fridayProducts = collect($friday->json('data.products'))->keyBy('name');
        $this->assertSame(4, $fridayProducts['FridayShawarma']['quantity']);
        $this->assertFalse($fridayProducts->has('Latte'));   // Wednesday excluded

        // Wednesday only → the breakfast/dinner orders, not Friday's.
        $wednesday = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?days_of_week[]=3')->assertOk();
        $wednesdayProducts = collect($wednesday->json('data.products'))->keyBy('name');
        $this->assertSame(3, $wednesdayProducts['Latte']['quantity']);
        $this->assertFalse($wednesdayProducts->has('FridayShawarma'));

        // Both days selected → both products present.
        $both = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?days_of_week[]=3&days_of_week[]=5')->assertOk();
        $bothProducts = collect($both->json('data.products'))->keyBy('name');
        $this->assertTrue($bothProducts->has('Latte'));
        $this->assertTrue($bothProducts->has('FridayShawarma'));
    }

    public function test_day_of_week_filter_applies_to_dining_area_report(): void
    {
        $this->seedOrders();   // Wednesday orders in indoor + outdoor
        $this->makeOrder($this->outdoor, '2026-07-17 20:00', [
            ['name' => 'FridayGrill', 'qty' => 1, 'line_total' => 120],
        ], 120);

        // Wednesday only: outdoor keeps its 1 Wednesday dinner order, not Friday's.
        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/dining-areas?days_of_week[]=3')->assertOk();
        $areas = collect($res->json('data.areas'))->keyBy('id');
        $this->assertSame(2, $areas[$this->indoor->id]['total_orders']);
        $this->assertSame(1, $areas[$this->outdoor->id]['total_orders']);
    }

    public function test_day_of_week_rejects_out_of_range_value(): void
    {
        $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?days_of_week[]=9')
            ->assertStatus(422)
            ->assertJsonValidationErrors('days_of_week.0');
    }

    public function test_time_window_filters_dining_area_orders(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/dining-areas?time_from=09:00&time_to=11:00')->assertOk();

        $areas = collect($res->json('data.areas'))->keyBy('id');
        $this->assertSame(2, $areas[$this->indoor->id]['total_orders']);   // both breakfast
        $this->assertSame(0, $areas[$this->outdoor->id]['total_orders']);  // dinner excluded
    }

    public function test_time_filter_rejects_bad_format(): void
    {
        $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?time_from=25:99')
            ->assertStatus(422)
            ->assertJsonValidationErrors('time_from');
    }

    public function test_dining_area_report_returns_per_area_totals_and_rolls_up(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/dining-areas')->assertOk();

        $areas = collect($res->json('data.areas'))->keyBy('id');

        // Indoor: 2 real orders (cancelled excluded), sales 120, AOV 60.
        $this->assertSame(2, $areas[$this->indoor->id]['total_orders']);
        $this->assertEquals(120.0, $areas[$this->indoor->id]['total_sales']);
        $this->assertEquals(60.0, $areas[$this->indoor->id]['avg_order_value']);

        // Outdoor: 1 order, sales 300, AOV 300.
        $this->assertSame(1, $areas[$this->outdoor->id]['total_orders']);
        $this->assertEquals(300.0, $areas[$this->outdoor->id]['avg_order_value']);

        // Indoor vs outdoor roll-up.
        $byType = collect($res->json('data.by_type'))->keyBy('type');
        $this->assertSame(2, $byType['indoor']['total_orders']);
        $this->assertSame(1, $byType['outdoor']['total_orders']);
        $this->assertSame(3, $res->json('data.totals.total_orders'));
    }

    public function test_export_returns_csv_file_with_product_rows(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->get('/api/dashboard/reports/products-by-time/export?format=csv')
            ->assertOk();

        $this->assertStringContainsString('text/csv', $res->headers->get('Content-Type'));
        $body = $res->streamedContent();
        $this->assertStringContainsString('Latte', $body);
        $this->assertStringContainsString('Product', $body);
    }

    public function test_export_returns_xlsx_file(): void
    {
        $this->seedOrders();

        $res = $this->actingAs($this->admin)
            ->get('/api/dashboard/reports/products-by-time/export?format=xlsx')
            ->assertOk();

        $this->assertStringContainsString('spreadsheetml', $res->headers->get('Content-Type'));
    }

    public function test_endpoints_forbidden_without_feature(): void
    {
        $this->restaurant->features()->where('feature_key', 'product_analytics')->update(['is_enabled' => false]);

        $this->actingAs($this->admin)->getJson('/api/dashboard/reports/products-by-time')->assertStatus(403);
        $this->actingAs($this->admin)->getJson('/api/dashboard/reports/dining-areas')->assertStatus(403);
        $this->actingAs($this->admin)->get('/api/dashboard/reports/products-by-time/export?format=csv')->assertStatus(403);
    }

    public function test_report_rejects_excessively_large_date_range(): void
    {
        // ~6 years > the 366-day cap → validation error, no unbounded query.
        $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?date_from=2020-01-01&date_to=2026-01-01')
            ->assertStatus(422)
            ->assertJsonValidationErrors('date_to');
    }

    public function test_report_rejects_inverted_date_range(): void
    {
        $this->actingAs($this->admin)
            ->getJson('/api/dashboard/reports/products-by-time?date_from=2026-01-10&date_to=2026-01-01')
            ->assertStatus(422)
            ->assertJsonValidationErrors('date_to');
    }
}

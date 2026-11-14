<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuSession;
use App\Models\Order;
use App\Models\OrderRound;
use App\Models\Restaurant;
use App\Models\TableVisit;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\Concerns\BuildsDinerOrders;
use Tests\TestCase;

class OrderTableAssociationTest extends TestCase
{
    use BuildsDinerOrders;
    use RefreshDatabase;

    private Restaurant $restaurant;

    private DiningTable $table;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->withOrdering()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'cafe',
        ]);
        $branch = new Branch(['name_en' => 'Main']);
        $branch->restaurant_id = $this->restaurant->id;
        $branch->save();
        $area = new DiningArea(['branch_id' => $branch->id, 'name_en' => 'Indoor']);
        $area->restaurant_id = $this->restaurant->id;
        $area->save();
        $this->table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => '12',
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $this->table->restaurant_id = $this->restaurant->id;
        $this->table->branch_id = $branch->id;
        $this->table->save();
    }

    private function makeSession(): MenuSession
    {
        $s = new MenuSession([
            'branch_id' => $this->table->branch_id,
            'dining_area_id' => $this->table->dining_area_id,
            'table_id' => $this->table->id,
            'language' => 'en',
            'session_token' => Str::random(40),
            'started_at' => now(), 'last_activity_at' => now(), 'expires_at' => now()->addHours(4),
        ]);
        $s->restaurant_id = $this->restaurant->id;
        $s->save();

        return $s;
    }

    private function orderPayload(array $extra = []): array
    {
        return array_merge([
            'items' => $this->dinerItems([['name' => 'Latte', 'qty' => 1, 'line_total' => 50]]),
            'total' => 50,
        ], $extra);
    }

    public function test_order_with_session_token_is_bound_to_the_table(): void
    {
        $session = $this->makeSession();

        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
            'order_type' => 'pickup', // should be overridden to dine_in
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertSame($this->table->id, $order->table_id);
        $this->assertSame($this->table->dining_area_id, $order->dining_area_id);
        $this->assertSame($this->table->branch_id, $order->branch_id);
        $this->assertSame($session->id, $order->menu_session_id);
        $this->assertSame('dine_in', $order->order_type);
    }

    public function test_order_without_session_is_unbound(): void
    {
        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'order_type' => 'delivery',
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertNull($order->table_id);
        $this->assertSame('delivery', $order->order_type);
    }

    public function test_later_table_submission_is_added_to_same_order_as_new_round(): void
    {
        $firstSession = $this->makeSession();
        $secondSession = $this->makeSession();

        $firstId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $firstSession->session_token,
        ]))->assertCreated()->json('data.id');

        $secondId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $secondSession->session_token,
            'items' => $this->dinerItems([['name' => 'Cake', 'qty' => 2, 'line_total' => 80]]),
            'total' => 80,
        ]))->assertCreated()->json('data.id');

        $this->assertSame($firstId, $secondId);
        $order = Order::withoutGlobalScopes()->findOrFail($firstId);
        $this->assertSame(130.0, (float) $order->total);
        $this->assertCount(2, $order->items);
        $this->assertSame(2, OrderRound::withoutGlobalScopes()->where('order_id', $order->id)->count());
        $this->assertSame(
            $firstSession->fresh()->table_visit_id,
            $secondSession->fresh()->table_visit_id,
        );
    }

    public function test_expired_table_session_cannot_submit_an_order(): void
    {
        $session = $this->makeSession();
        $session->forceFill(['expires_at' => now()->subMinute()])->save();

        $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
        ]))->assertStatus(422);

        $this->assertDatabaseCount('orders', 0);
    }

    public function test_new_scan_after_visit_ttl_starts_a_fresh_order(): void
    {
        $firstSession = $this->makeSession();
        $firstOrderId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $firstSession->session_token,
        ]))->assertCreated()->json('data.id');

        $firstVisitId = $firstSession->fresh()->table_visit_id;
        TableVisit::withoutGlobalScopes()->findOrFail($firstVisitId)
            ->forceFill(['opened_at' => now()->subHours(5)])->save();

        $nextSession = $this->makeSession();
        $nextOrderId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $nextSession->session_token,
        ]))->assertCreated()->json('data.id');

        $this->assertNotSame($firstOrderId, $nextOrderId);
        $this->assertNotSame($firstVisitId, $nextSession->fresh()->table_visit_id);
        $this->assertSame('COMPLETED', Order::withoutGlobalScopes()->findOrFail($firstOrderId)->status->value);
    }

    public function test_staff_can_close_visit_and_revoke_every_session(): void
    {
        app(RestaurantFeatureService::class)->apply($this->restaurant, [
            'qr_menu' => true,
            'system_ordering' => true,
            'table_management' => true,
        ]);
        $admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $session = $this->makeSession();
        $orderId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
        ]))->assertCreated()->json('data.id');

        $this->actingAs($admin)->postJson("/api/dashboard/tables/{$this->table->id}/visit/finish", [
            'status' => 'CLOSED',
        ])->assertOk()->assertJsonPath('data.status', 'CLOSED');

        $this->assertSame('COMPLETED', Order::withoutGlobalScopes()->findOrFail($orderId)->status->value);
        $this->assertNotNull($session->fresh()->closed_at);
        $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
        ]))->assertStatus(422);
    }

    public function test_cancelling_a_visit_records_who_cancelled_its_order(): void
    {
        app(RestaurantFeatureService::class)->apply($this->restaurant, [
            'qr_menu' => true,
            'system_ordering' => true,
            'table_management' => true,
        ]);
        $admin = User::factory()->restaurantAdmin($this->restaurant->id)->create();
        $session = $this->makeSession();
        $orderId = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => $session->session_token,
        ]))->assertCreated()->json('data.id');

        $this->actingAs($admin)->postJson("/api/dashboard/tables/{$this->table->id}/visit/finish", [
            'status' => 'CANCELLED',
        ])->assertOk();

        $order = Order::withoutGlobalScopes()->findOrFail($orderId);
        $this->assertSame('CANCELLED', $order->status->value);
        $this->assertSame($admin->id, $order->cancelled_by);
        $this->assertNotNull($order->cancelled_at);
        $this->assertNull($order->cancellation_reason);
    }

    public function test_stale_session_token_still_records_the_order_untagged(): void
    {
        $res = $this->postJson('/api/public/restaurants/cafe/orders', $this->orderPayload([
            'session_token' => Str::random(40), // never issued
        ]))->assertCreated();

        $order = Order::findOrFail($res->json('data.id'));
        $this->assertNull($order->table_id);
    }
}

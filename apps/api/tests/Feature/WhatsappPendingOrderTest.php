<?php

namespace Tests\Feature;

use App\Enums\OrderingMode;
use App\Enums\OrderStatus;
use App\Enums\TenantCapability;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\BuildsDinerOrders;
use Tests\TestCase;

/**
 * live-board-to-pos D6/D13/D14: a WhatsApp restaurant's checkout is recorded as
 * a PENDING order; an employee accepts it (it becomes a normal NEW order) or
 * rejects it (CANCELLED). Pending is never a sale, a kitchen order or a badge.
 */
class WhatsappPendingOrderTest extends TestCase
{
    use BuildsDinerOrders;
    use RefreshDatabase;

    /** A restaurant entitled to ordering whose chosen channel is WhatsApp. */
    private function restaurant(string $slug = 'wa'): Restaurant
    {
        return Restaurant::factory()->withOrdering()->create(['slug' => $slug, 'ordering_mode' => OrderingMode::WHATSAPP]);
    }

    private function payload(?Restaurant $r = null): array
    {
        return [
            'items' => $this->dinerItems([['name' => 'Pizza', 'qty' => 1, 'options' => [], 'line_total' => 80]], $r),
            'total' => 80,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
        ];
    }

    private function place(Restaurant $r): int
    {
        return $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload($r))
            ->assertCreated()->json('data.id');
    }

    private function staffWith(Restaurant $r, array $caps): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $r->id,
            'capabilities' => TenantCapability::expand($caps),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($r->id, $role->id)->create();
    }

    public function test_whatsapp_checkout_records_a_pending_order(): void
    {
        $r = $this->restaurant();

        $id = $this->place($r);

        $this->assertDatabaseHas('orders', [
            'id' => $id, 'restaurant_id' => $r->id,
            'status' => 'PENDING', 'source' => 'whatsapp', 'customer_name' => 'Amer',
        ]);
        $this->assertNull(Order::withoutGlobalScopes()->find($id)->pickup_token);
    }

    public function test_a_whatsapp_order_needs_a_phone_number(): void
    {
        $r = $this->restaurant();
        $payload = $this->payload($r);
        unset($payload['customer_phone']);

        $this->postJson('/api/public/restaurants/wa/orders', $payload)
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.whatsapp_order_needs_phone'));
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_a_paused_whatsapp_restaurant_still_refuses_orders(): void
    {
        $r = Restaurant::factory()->withOrdering()->create([
            'slug' => 'wa', 'ordering_mode' => OrderingMode::WHATSAPP, 'accepts_orders' => false,
        ]);

        $this->postJson('/api/public/restaurants/wa/orders', $this->payload($r))->assertStatus(422);
        $this->assertDatabaseCount('orders', 0);
    }

    public function test_pending_orders_are_listed_but_not_counted_as_new_or_sales(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->place($r);

        $this->actingAs($admin)->getJson('/api/dashboard/orders')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.status', 'PENDING')
            ->assertJsonPath('summary.metrics.new_orders', 0)
            ->assertJsonPath('summary.metrics.pending_orders', 1)
            ->assertJsonPath('summary.counts.PENDING', 1);

        $this->actingAs($admin)->getJson('/api/dashboard/orders/new-count')
            ->assertOk()
            ->assertJsonPath('data.new_orders', 0)
            ->assertJsonPath('data.pending_orders', 1);

        // Not a sale until accepted: the stats counter starts at 0, then moves.
        $this->actingAs($admin)->getJson('/api/dashboard/stats')
            ->assertOk()->assertJsonPath('data.orders_today', 0)->assertJsonPath('data.new_orders', 0);

        $id = Order::withoutGlobalScopes()->value('id');
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();
        $this->actingAs($admin)->getJson('/api/dashboard/stats')
            ->assertOk()->assertJsonPath('data.orders_today', 1)->assertJsonPath('data.new_orders', 1);
    }

    public function test_accept_turns_a_pending_order_into_a_new_one_and_is_idempotent(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")
            ->assertOk()->assertJsonPath('data.status', 'NEW');
        // A second tap (or a second employee) changes nothing and is not an error.
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")
            ->assertOk()->assertJsonPath('data.status', 'NEW');

        $this->assertSame(OrderStatus::NEW, Order::withoutGlobalScopes()->find($id)->status);
        $this->actingAs($admin)->getJson('/api/dashboard/orders/new-count')
            ->assertJsonPath('data.new_orders', 1)->assertJsonPath('data.pending_orders', 0);
    }

    public function test_reject_cancels_with_a_reason_and_who_did_it(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/reject", ['reason' => 'Closed'])
            ->assertOk()->assertJsonPath('data.status', 'CANCELLED');

        $order = Order::withoutGlobalScopes()->find($id);
        $this->assertSame('Closed', $order->cancellation_reason);
        $this->assertSame($admin->id, $order->cancelled_by);
        $this->assertNotNull($order->cancelled_at);
    }

    public function test_a_decided_order_cannot_be_decided_the_other_way(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $accepted = $this->place($r);
        $rejected = $this->place($r);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$accepted}/accept")->assertOk();
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$rejected}/reject")->assertOk();

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$accepted}/reject")->assertStatus(422);
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$rejected}/accept")->assertStatus(422);
        $this->assertSame(OrderStatus::NEW, Order::withoutGlobalScopes()->find($accepted)->status);
        $this->assertSame(OrderStatus::CANCELLED, Order::withoutGlobalScopes()->find($rejected)->status);
    }

    public function test_nothing_can_be_moved_back_to_pending(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$id}/status", ['status' => 'PENDING'])
            ->assertStatus(422);

        $this->assertFalse(OrderStatus::COMPLETED->canTransitionTo(OrderStatus::PENDING));
        $this->assertFalse(OrderStatus::CANCELLED->canTransitionTo(OrderStatus::PENDING));
        $this->assertFalse(OrderStatus::PENDING->canTransitionTo(OrderStatus::COMPLETED));
    }

    public function test_another_restaurants_pending_order_is_a_404(): void
    {
        $mine = $this->restaurant('mine');
        $theirs = $this->restaurant('theirs');
        $admin = User::factory()->restaurantAdmin($mine->id)->create();
        $foreign = $this->place($theirs);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$foreign}/accept")->assertNotFound();
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$foreign}/reject")->assertNotFound();
        $this->assertSame(OrderStatus::PENDING, Order::withoutGlobalScopes()->find($foreign)->status);
    }

    public function test_deciding_needs_the_orders_update_capability(): void
    {
        $r = $this->restaurant();
        $id = $this->place($r);
        $viewer = $this->staffWith($r, ['orders.view']);

        $this->actingAs($viewer)->postJson("/api/dashboard/orders/{$id}/accept")->assertForbidden();
        $this->actingAs($viewer)->postJson("/api/dashboard/orders/{$id}/reject")->assertForbidden();
        $this->assertSame(OrderStatus::PENDING, Order::withoutGlobalScopes()->find($id)->status);

        $manager = $this->staffWith($r, ['orders.view', 'orders.update']);
        $this->actingAs($manager)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();
    }

    public function test_a_whatsapp_only_plan_reaches_the_order_queue(): void
    {
        // No system_ordering and no pos: before this change the queue was closed to it.
        $r = Restaurant::factory()->create(['slug' => 'wa-only', 'ordering_mode' => OrderingMode::WHATSAPP]);
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'whatsapp_ordering' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        $this->actingAs($admin)->getJson('/api/dashboard/orders')->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();
    }

    public function test_a_plan_with_no_ordering_feature_still_has_no_queue(): void
    {
        $r = Restaurant::factory()->create();
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/orders')->assertForbidden();
    }

    public function test_the_pulse_counts_pending_orders_for_a_whatsapp_only_plan(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'wa-only', 'ordering_mode' => OrderingMode::WHATSAPP]);
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'whatsapp_ordering' => true]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->place($r);

        $this->actingAs($admin)->getJson('/api/dashboard/pulse')
            ->assertOk()->assertJsonPath('data.pending_orders', 1);
    }

    public function test_insights_do_not_count_a_pending_order(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()->assertJsonPath('data.engagement.orders_total', 0);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();
        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()->assertJsonPath('data.engagement.orders_total', 1);
    }

    public function test_a_pending_order_cannot_be_moved_by_the_generic_status_route(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        foreach (['NEW', 'COMPLETED', 'CANCELLED'] as $status) {
            $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$id}/status", ['status' => $status])
                ->assertStatus(422);
        }
        $this->assertSame(OrderStatus::PENDING, Order::withoutGlobalScopes()->find($id)->status);
    }

    public function test_accepting_marks_the_orders_new_order_alert_read(): void
    {
        $r = $this->restaurant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $id = $this->place($r);

        // The alert the checkout recorded for this order (found by id, as the
        // test app re-runs terminating callbacks after later requests).
        $alert = Notification::withoutGlobalScopes()->where('type', 'order.created')
            ->where('data->order_id', (string) $id)->firstOrFail();
        $this->assertNull($alert->read_at);

        $this->actingAs($admin)->postJson("/api/dashboard/orders/{$id}/accept")->assertOk();

        $this->assertNotNull($alert->fresh()->read_at);
    }

    public function test_a_system_restaurants_checkout_is_still_new(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'sys']);

        $this->postJson('/api/public/restaurants/sys/orders', $this->payload($r))->assertCreated();

        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'status' => 'NEW', 'source' => 'system']);
    }
}

<?php

namespace Tests\Feature;

use Tests\Concerns\BuildsDinerOrders;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class OrderTest extends TestCase
{
    use BuildsDinerOrders;

    use RefreshDatabase;

    /** Order management is gated on the system_ordering feature. */
    private function enableSystemOrdering(Restaurant $r): void
    {
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true]);
    }

    private function payload(?Restaurant $restaurant = null): array
    {
        return [
            'items' => $this->dinerItems([
                ['name' => 'برجر', 'qty' => 2, 'options' => ['جبنة إضافية'], 'note' => 'بدون بصل', 'line_total' => 150],
                ['name' => 'Pizza', 'qty' => 1, 'variant' => 'Medium', 'options' => [], 'note' => null, 'line_total' => 80],
            ], $restaurant),
            'total' => 230,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
        ];
    }

    public function test_guest_can_record_an_order(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $res = $this->postJson('/api/public/restaurants/demo/orders', $this->payload());

        $res->assertCreated()->assertJsonPath('data.code', 'ORD-'.$res->json('data.id'));
        $this->assertDatabaseHas('orders', [
            'restaurant_id' => $r->id,
            'status' => 'NEW',
            'customer_name' => 'Amer',
            'source' => 'system',
        ]);
    }

    /** The menu always sends the directory-only fields (email, address) — they must not break the order row. */
    public function test_order_accepts_customer_email_and_address_fields(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $this->postJson('/api/public/restaurants/demo/orders', $this->payload() + [
            'customer_email' => 'amer@example.com',
            'customer_address' => '12 Nile St, Cairo',
            'address_label' => 'Home',
            'note' => null,
        ])->assertCreated();

        $this->assertDatabaseHas('orders', ['restaurant_id' => $r->id, 'customer_name' => 'Amer']);
        $this->assertDatabaseHas('customers', ['restaurant_id' => $r->id, 'email' => 'amer@example.com']);
    }

    /** A size/portion pick is kept apart from the add-ons on both the JSON snapshot and the round line. */
    public function test_order_keeps_the_chosen_variant(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $id = $this->postJson('/api/public/restaurants/demo/orders', $this->payload())
            ->assertCreated()->json('data.id');

        $order = Order::withoutGlobalScopes()->findOrFail($id);
        $this->assertSame('Medium', $order->items[1]['variant']);
        $this->assertArrayNotHasKey('variant', $order->items[0]);

        $this->assertDatabaseHas('order_items', [
            'order_id' => $id, 'name' => 'Pizza', 'variant' => 'Medium',
        ]);
        $this->assertDatabaseHas('order_items', [
            'order_id' => $id, 'name' => 'برجر', 'variant' => null, 'note' => 'بدون بصل',
        ]);
        $this->assertSame('بدون بصل', $order->items[0]['note']);

        $this->enableSystemOrdering($r);
        $this->actingAs(User::factory()->restaurantAdmin($r->id)->create())
            ->getJson('/api/dashboard/orders')
            ->assertOk()
            ->assertJsonPath('data.0.items.1.variant', 'Medium')
            ->assertJsonPath('data.0.items.0.note', 'بدون بصل')
            ->assertJsonPath('data.0.rounds.0.items.1.variant', 'Medium')
            ->assertJsonPath('data.0.rounds.0.items.0.note', 'بدون بصل');
    }

    public function test_order_total_is_recomputed_from_line_totals_not_trusted(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        // Client sends a forged total that doesn't match its line items.
        $this->postJson('/api/public/restaurants/demo/orders', [
            'items' => $this->dinerItems([
                ['name' => 'Burger', 'qty' => 2, 'line_total' => 150],
                ['name' => 'Pizza', 'qty' => 1, 'line_total' => 80],
            ]),
            'total' => 0.01,
            'customer_phone' => '+201234567890',
        ])->assertCreated();

        // Stored total is the sum of the line totals (230), not the forged 0.01.
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->firstOrFail();
        $this->assertEquals(230.0, (float) $order->total);
    }

    public function test_order_total_is_clamped_to_the_column_capacity(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        // 100 lines × 1,000,000 = 100,000,000 would overflow decimal(10,2) on
        // Postgres; the recompute must clamp to the column max, never 500.
        $items = array_fill(0, 100, ['name' => 'X', 'qty' => 1, 'line_total' => 1000000]);
        $this->postJson('/api/public/restaurants/demo/orders', [
            'items' => $this->dinerItems($items),
            'total' => 100,
            'customer_phone' => '+201234567890',
        ])->assertCreated();

        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->firstOrFail();
        $this->assertEquals(99999999.99, (float) $order->total);
    }

    public function test_order_requires_items(): void
    {
        Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);

        $this->postJson('/api/public/restaurants/demo/orders', ['items' => [], 'total' => 0])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['items']);
    }

    public function test_hidden_restaurant_rejects_orders(): void
    {
        Restaurant::factory()->suspended()->withOrdering()->create(['slug' => 'closed']);

        $this->postJson('/api/public/restaurants/closed/orders', $this->payload())
            ->assertNotFound();
    }

    public function test_ordering_disabled_rejects_orders(): void
    {
        // No ordering entitlement on the plan → the public menu is display-only.
        Restaurant::factory()->create(['slug' => 'view-only']);

        $this->postJson('/api/public/restaurants/view-only/orders', $this->payload())
            ->assertStatus(422);
    }

    public function test_admin_sees_only_own_orders(): void
    {
        $mine = Restaurant::factory()->create();
        $other = Restaurant::factory()->withOrdering()->create();
        $admin = User::factory()->restaurantAdmin($mine->id)->create();
        $this->enableSystemOrdering($mine);

        $this->postJson("/api/public/restaurants/{$mine->slug}/orders", $this->payload($mine))->assertCreated();
        $this->postJson("/api/public/restaurants/{$other->slug}/orders", $this->payload($other))->assertCreated();

        $this->actingAs($admin)->getJson('/api/dashboard/orders')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->actingAs($admin)->getJson('/api/dashboard/orders/new-count')
            ->assertOk()
            ->assertJsonPath('data.new_orders', 1);
    }

    public function test_admin_can_update_order_status_but_not_foreign_orders(): void
    {
        $mine = Restaurant::factory()->create();
        $other = Restaurant::factory()->withOrdering()->create();
        $admin = User::factory()->restaurantAdmin($mine->id)->create();
        $this->enableSystemOrdering($mine);

        $this->postJson("/api/public/restaurants/{$mine->slug}/orders", $this->payload($mine));
        $this->postJson("/api/public/restaurants/{$other->slug}/orders", $this->payload($other));

        $myOrder = Order::withoutGlobalScopes()->where('restaurant_id', $mine->id)->first();
        $foreignOrder = Order::withoutGlobalScopes()->where('restaurant_id', $other->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$myOrder->id}/status", ['status' => 'COMPLETED'])
            ->assertOk()
            ->assertJsonPath('data.status', 'COMPLETED');

        // Cross-tenant access is a 404, never a 403 (information hiding).
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$foreignOrder->id}/status", ['status' => 'COMPLETED'])
            ->assertNotFound();
    }

    public function test_acting_on_an_order_marks_its_new_order_notification_read(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);

        // Placing the order records an unread 'order.created' notification whose
        // data.order_id links back to the order (via terminating callbacks).
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload())->assertCreated();
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $notification = Notification::withoutGlobalScopes()
            ->where('restaurant_id', $r->id)
            ->where('type', 'order.created')
            ->first();
        $this->assertNull($notification->read_at);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk();

        $this->assertNotNull($notification->fresh()->read_at);
    }

    public function test_order_status_rejects_unknown_value(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'BOGUS'])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['status']);
    }

    public function test_a_completed_order_cannot_be_reopened_to_new(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk();

        // Reopening a terminal order back to NEW would corrupt the new-orders
        // badge and reporting — reject it and leave the status untouched.
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'NEW'])
            ->assertStatus(422);
        $this->assertSame('COMPLETED', $order->fresh()->status->value);
    }

    public function test_a_completed_order_can_be_corrected_to_cancelled(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk();

        // Staff may still correct a mistake between the two terminal states.
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED'])
            ->assertOk()
            ->assertJsonPath('data.status', 'CANCELLED');
    }

    public function test_cancelling_records_reason_time_and_who(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", [
            'status' => 'CANCELLED',
            'reason' => '  Customer did not answer the phone  ',
        ])
            ->assertOk()
            ->assertJsonPath('data.status', 'CANCELLED')
            ->assertJsonPath('data.cancellation_reason', 'Customer did not answer the phone')
            ->assertJsonPath('data.cancelled_by_name', $admin->name);

        $fresh = $order->fresh();
        $this->assertNotNull($fresh->cancelled_at);
        $this->assertSame($admin->id, $fresh->cancelled_by);

        // The list carries the same fields, so the receipt dialog can show them.
        $this->actingAs($admin)->getJson('/api/dashboard/orders?status=CANCELLED')
            ->assertOk()
            ->assertJsonPath('data.0.cancellation_reason', 'Customer did not answer the phone');
    }

    public function test_the_cancellation_reason_is_optional(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        // An empty reason is stored as null, not as an empty string.
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED', 'reason' => '   '])
            ->assertOk()
            ->assertJsonPath('data.cancellation_reason', null);
        $this->assertNotNull($order->fresh()->cancelled_at);
    }

    public function test_the_cancellation_reason_is_length_limited(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED', 'reason' => str_repeat('x', 256)])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['reason']);
        $this->assertSame('NEW', $order->fresh()->status->value);
    }

    public function test_correcting_a_cancellation_clears_its_reason(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED', 'reason' => 'Wrong order'])
            ->assertOk();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk()
            ->assertJsonPath('data.cancellation_reason', null)
            ->assertJsonPath('data.cancelled_at', null);

        $fresh = $order->fresh();
        $this->assertNull($fresh->cancelled_by);
        $this->assertNull($fresh->cancellation_reason);
    }

    public function test_a_reason_sent_with_a_completion_is_ignored(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED', 'reason' => 'nope'])
            ->assertOk()
            ->assertJsonPath('data.cancellation_reason', null);
    }

    public function test_completing_records_who_when_and_how_long(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);

        Carbon::setTestNow('2026-11-03 10:00:00');
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload())->assertCreated();
        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();

        Carbon::setTestNow('2026-11-03 10:17:40');
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk()
            ->assertJsonPath('data.handled_by_name', $admin->name)
            ->assertJsonPath('data.minutes_to_complete', 17)
            // An online order records no payment, so it claims none.
            ->assertJsonPath('data.payment_status', null);
        $this->assertSame($admin->id, $order->fresh()->completed_by);

        // Corrected to cancelled: the completion stamp goes, the cancel one comes.
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED'])
            ->assertOk()
            ->assertJsonPath('data.completed_at', null)
            ->assertJsonPath('data.minutes_to_complete', null)
            ->assertJsonPath('data.handled_by_name', $admin->name);
        $this->assertNull($order->fresh()->completed_by);
        Carbon::setTestNow();
    }

    public function test_orders_filter_by_restaurant_local_date_range(): void
    {
        // Cairo is UTC+2 in November. An order at 23:30 local on the 2nd is
        // 21:30 UTC — it belongs to the 2nd, never the 3rd.
        $r = Restaurant::factory()->create(['timezone' => 'Africa/Cairo']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);

        foreach (['2026-11-01 10:00:00', '2026-11-02 21:30:00', '2026-11-03 09:00:00'] as $utc) {
            Carbon::setTestNow($utc);
            $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload())->assertCreated();
        }
        Carbon::setTestNow();

        $this->actingAs($admin)->getJson('/api/dashboard/orders?from=2026-11-02&to=2026-11-02')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('summary.counts.all', 1);
        $this->actingAs($admin)->getJson('/api/dashboard/orders?from=2026-11-02')
            ->assertOk()->assertJsonCount(2, 'data');
        $this->actingAs($admin)->getJson('/api/dashboard/orders?to=2026-11-01')
            ->assertOk()->assertJsonCount(1, 'data');

        // A range that ends before it starts is a mistake, not an empty list.
        $this->actingAs($admin)->getJson('/api/dashboard/orders?from=2026-11-03&to=2026-11-01')
            ->assertStatus(422)->assertJsonValidationErrors(['to']);
    }

    public function test_orders_export_is_a_csv_of_the_filtered_list(): void
    {
        $r = Restaurant::factory()->create(['default_language' => 'en']);
        $other = Restaurant::factory()->withOrdering()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);

        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload($r))->assertCreated();
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", array_merge($this->payload($r), ['customer_name' => 'Second Guest']))->assertCreated();
        $this->postJson("/api/public/restaurants/{$other->slug}/orders", array_merge($this->payload($other), ['customer_name' => 'Foreign Guest']))->assertCreated();

        $first = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->orderBy('id')->first();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$first->id}/status", ['status' => 'CANCELLED', 'reason' => 'No answer'])
            ->assertOk();

        $res = $this->actingAs($admin)->get('/api/dashboard/orders/export');
        $res->assertOk();
        $this->assertStringContainsString('text/csv', $res->headers->get('Content-Type'));
        $csv = $res->streamedContent();

        $this->assertStringStartsWith("\xEF\xBB\xBF", $csv, 'BOM so Excel reads Arabic');
        $lines = array_values(array_filter(explode("\n", trim(substr($csv, 3)))));
        $this->assertCount(3, $lines, 'header + this restaurant\'s two orders only');
        $this->assertStringContainsString('Order,"Placed at"', $lines[0]);
        $this->assertStringNotContainsString('Foreign Guest', $csv);
        $this->assertStringContainsString('No answer', $csv);
        $this->assertStringContainsString('Cancelled', $csv);
        $this->assertStringContainsString(',Online,', $csv, 'channel is a word, not an internal code');

        // The status filter narrows the export just as it narrows the list.
        $onlyNew = $this->actingAs($admin)->get('/api/dashboard/orders/export?status=NEW')->streamedContent();
        $this->assertStringContainsString('Second Guest', $onlyNew);
        $this->assertStringNotContainsString('No answer', $onlyNew);
    }

    public function test_orders_export_needs_the_orders_capability(): void
    {
        $r = Restaurant::factory()->create();
        $this->enableSystemOrdering($r);
        $role = new Role(['name' => 'Menu only']);
        $role->forceFill(['restaurant_id' => $r->id, 'capabilities' => ['menu.view']])->save();
        $staff = User::factory()->staff($r->id, $role->id)->create();

        $this->actingAs($staff)->get('/api/dashboard/orders/export')->assertForbidden();
    }

    public function test_public_can_read_own_order_status(): void
    {
        $r = Restaurant::factory()->withOrdering()->create(['slug' => 'demo']);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);

        $id = $this->postJson('/api/public/restaurants/demo/orders', $this->payload())
            ->assertCreated()->json('data.id');

        // Freshly placed → NEW; the endpoint returns only the status.
        $this->getJson("/api/public/restaurants/demo/orders/{$id}/status")
            ->assertOk()
            ->assertExactJson(['data' => ['status' => 'NEW']]);

        // Once the restaurant closes it, the same endpoint reports COMPLETED —
        // this is what tells the menu SPA to invite feedback on the next visit.
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$id}/status", ['status' => 'COMPLETED'])
            ->assertOk();

        $this->getJson("/api/public/restaurants/demo/orders/{$id}/status")
            ->assertOk()
            ->assertJsonPath('data.status', 'COMPLETED');
    }

    public function test_public_order_status_is_scoped_to_the_restaurant(): void
    {
        $mine = Restaurant::factory()->withOrdering()->create(['slug' => 'mine']);
        $other = Restaurant::factory()->withOrdering()->create(['slug' => 'other']);

        $id = $this->postJson('/api/public/restaurants/other/orders', $this->payload())
            ->json('data.id');

        // Another restaurant's order id resolves to 404 through my slug — never a
        // cross-tenant status leak, and unknown ids 404 too.
        $this->getJson("/api/public/restaurants/mine/orders/{$id}/status")->assertNotFound();
        $this->getJson('/api/public/restaurants/mine/orders/999999/status')->assertNotFound();
    }

    public function test_orders_filter_by_status(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload());

        $order = Order::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED']);

        $this->actingAs($admin)->getJson('/api/dashboard/orders?status=NEW')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }
}

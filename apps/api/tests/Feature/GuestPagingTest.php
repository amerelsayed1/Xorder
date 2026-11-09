<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Enums\PickupStatus;
use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\Category;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\MenuSession;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\GuestPagingService;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Guest paging, stage S1 (docs/features/guest-paging/FEATURE.md): the pickup
 * lifecycle beside OrderStatus, the dashboard board and its two buttons.
 */
class GuestPagingTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    private function tenant(bool $paging = true): Restaurant
    {
        $r = Restaurant::factory()->withOrdering()->create();
        app(RestaurantFeatureService::class)->apply($r, [
            'qr_menu' => true, 'system_ordering' => true, 'guest_paging' => $paging,
        ]);

        return $r->fresh();
    }

    /** A diner order as the menu sends it now: ids and quantities, priced by the server. */
    private function payload(Restaurant $r): array
    {
        $category = Category::factory()->create(['restaurant_id' => $r->id]);
        $latte = MenuItem::factory()->create([
            'restaurant_id' => $r->id, 'category_id' => $category->id,
            'name_en' => 'Latte', 'name_ar' => 'لاتيه', 'price' => 60,
        ]);

        return [
            'items' => [['kind' => 'item', 'menu_item_id' => $latte->id, 'qty' => 1]],
            'total' => 60,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
            'order_type' => 'pickup',
        ];
    }

    /** A QR order, then the pickup fields S2 will write at creation. */
    private function pagedOrder(Restaurant $r, array $extra = []): Order
    {
        $id = $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload($r))
            ->assertCreated()->json('data.id');

        $order = Order::withoutGlobalScopes()->findOrFail($id);
        $order->forceFill($extra + [
            'pickup_token' => GuestPagingService::generateToken(),
            'pickup_status' => PickupStatus::PREPARING->value,
            'pickup_display_ref' => $order->code(),
        ])->save();

        return $order->fresh();
    }

    private function staffWith(Restaurant $r, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $r->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($r->id, $role->id)->create();
    }

    // ---- the flag (AC-1)

    public function test_guest_paging_is_sold_not_inherited(): void
    {
        $this->assertFalse(Feature::defaultSet()['guest_paging']);
        $this->assertSame([], Feature::GUEST_PAGING->requires());
        $this->assertTrue(Feature::resolve(['guest_paging' => true])['guest_paging']);
    }

    public function test_board_and_pickup_are_forbidden_without_the_feature(): void
    {
        $r = $this->tenant(paging: false);
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        $this->actingAs($admin)->getJson('/api/dashboard/pickup-board')->assertForbidden();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])
            ->assertForbidden();
    }

    // ---- the lifecycle (AC-4)

    public function test_ready_stamps_once_and_replay_is_a_no_op(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        Carbon::setTestNow('2026-11-02 10:00:00');
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])
            ->assertOk()
            ->assertJsonPath('data.pickup_status', 'READY')
            ->assertJsonPath('data.ready_source', 'dashboard')
            ->assertJsonStructure(['data' => [
                'pickup_status', 'pickup_ref', 'pickup_followed_at', 'ready_at', 'ready_source',
                'acknowledged_at', 'picked_up_at',
            ]])
            ->assertJsonMissingPath('data.pickup_token')
            ->assertJsonMissingPath('data.pickup_push_token');

        $first = $order->fresh();
        $this->assertSame('2026-11-02T10:00:00+00:00', $first->ready_at->toIso8601String());
        $this->assertSame($admin->id, $first->ready_by);

        Carbon::setTestNow('2026-11-02 10:05:00');
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])
            ->assertOk();

        $this->assertSame('2026-11-02T10:00:00+00:00', $order->fresh()->ready_at->toIso8601String());
    }

    public function test_picked_up_follows_ready_and_completes_a_new_order(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);
        $this->assertSame('NEW', $order->status->value);

        $alert = Notification::withoutGlobalScopes()->where('restaurant_id', $r->id)
            ->where('type', 'order.created')->first();
        $this->assertNull($alert->read_at);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])->assertOk();
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'PICKED_UP'])
            ->assertOk()
            ->assertJsonPath('data.pickup_status', 'PICKED_UP')
            ->assertJsonPath('data.status', 'COMPLETED');

        $fresh = $order->fresh();
        $this->assertNotNull($fresh->picked_up_at);
        $this->assertNotNull($fresh->ready_at);
        $this->assertNotNull($alert->fresh()->read_at);
    }

    public function test_pickup_never_moves_backwards(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'PICKED_UP'])
            ->assertOk();
        $pickedUpAt = $order->fresh()->picked_up_at;

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])
            ->assertStatus(422);

        $fresh = $order->fresh();
        $this->assertSame('PICKED_UP', $fresh->pickup_status->value);
        $this->assertEquals($pickedUpAt, $fresh->picked_up_at);
        // Skipping Ready leaves ready_at honest (empty), so reports never count it.
        $this->assertNull($fresh->ready_at);
    }

    public function test_pickup_rejects_unknown_values_and_unpaged_orders(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // dine_in is outside the default paged types, so this order has no token.
        $id = $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => 'dine_in'] + $this->payload($r))
            ->json('data.id');

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$id}/pickup", ['status' => 'PREPARING'])
            ->assertStatus(422)->assertJsonValidationErrors(['status']);
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$id}/pickup", ['status' => 'READY'])
            ->assertStatus(422)->assertJsonPath('message', __('xorder.messages.order_not_paged'));
    }

    public function test_pickup_is_tenant_scoped_and_capability_gated(): void
    {
        $mine = $this->tenant();
        $other = $this->tenant();
        $admin = User::factory()->restaurantAdmin($mine->id)->create();
        $viewer = $this->staffWith($mine, ['orders.view']);
        $foreign = $this->pagedOrder($other);
        $own = $this->pagedOrder($mine);

        // Cross-tenant is a 404, never a 403 (information hiding).
        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$foreign->id}/pickup", ['status' => 'READY'])
            ->assertNotFound();
        $this->assertSame('PREPARING', $foreign->fresh()->pickup_status->value);

        // orders.view may watch the board but not press its buttons.
        $this->actingAs($viewer)->getJson('/api/dashboard/pickup-board')->assertOk();
        $this->actingAs($viewer)->patchJson("/api/dashboard/orders/{$own->id}/pickup", ['status' => 'READY'])
            ->assertForbidden();
    }

    public function test_completing_a_paged_order_from_the_queue_marks_it_picked_up(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'COMPLETED'])
            ->assertOk()
            ->assertJsonPath('data.pickup_status', 'PICKED_UP');

        $this->assertNotNull($order->fresh()->picked_up_at);
    }

    public function test_cancelling_leaves_the_pickup_fields_alone(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED'])
            ->assertOk()
            ->assertJsonPath('data.pickup_status', 'PREPARING');
        $this->assertNull($order->fresh()->picked_up_at);
    }

    public function test_a_cancelled_order_is_never_paged_forward(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r, ['status' => 'CANCELLED']);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/pickup", ['status' => 'READY'])
            ->assertStatus(422);

        $fresh = $order->fresh();
        $this->assertSame('PREPARING', $fresh->pickup_status->value);
        $this->assertNull($fresh->ready_at);
    }

    /** BR-2 helpers shipped in S1, consumed by the intake paths in S2/S5. */
    public function test_eligibility_follows_the_flag_and_the_paged_types(): void
    {
        $service = app(GuestPagingService::class);
        $r = $this->tenant();

        $this->assertSame(['takeaway', 'pickup', 'drive_thru'], $service->pagedOrderTypes($r));
        $this->assertTrue($service->isEligible($r, 'pickup'));
        $this->assertTrue($service->isEligible($r, 'takeaway'));
        $this->assertFalse($service->isEligible($r, 'dine_in'));
        $this->assertFalse($service->isEligible($r, 'delivery'));
        $this->assertFalse($service->isEligible($r, null));
        $this->assertFalse($service->isEligible($r, 'pickup', tableVisitRound: true));

        $r->forceFill(['guest_paging_order_types' => ['dine_in']])->save();
        $this->assertTrue($service->isEligible($r->fresh(), 'dine_in'));
        $this->assertFalse($service->isEligible($r->fresh(), 'pickup'));

        $r->forceFill(['guest_paging_order_types' => []])->save();
        $this->assertSame(['takeaway', 'pickup', 'drive_thru'], $service->pagedOrderTypes($r->fresh()));

        $off = $this->tenant(paging: false);
        $this->assertFalse($service->isEligible($off, 'pickup'));
    }

    // ---- the board (AC-5)

    public function test_board_lists_todays_paged_orders_and_computes_call_out(): void
    {
        Carbon::setTestNow('2026-11-02 12:00:00');
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $preparing = $this->pagedOrder($r);
        $ready = $this->pagedOrder($r, ['pickup_status' => 'READY', 'ready_at' => Carbon::now()->subMinutes(5)]);
        $acked = $this->pagedOrder($r, [
            'pickup_status' => 'READY', 'ready_at' => Carbon::now()->subMinutes(10), 'acknowledged_at' => Carbon::now(),
        ]);
        $recentPickup = $this->pagedOrder($r, ['pickup_status' => 'PICKED_UP', 'picked_up_at' => Carbon::now()->subMinutes(5)]);
        $oldPickup = $this->pagedOrder($r, ['pickup_status' => 'PICKED_UP', 'picked_up_at' => Carbon::now()->subMinutes(45)]);
        $cancelled = $this->pagedOrder($r, ['status' => 'CANCELLED']);
        $yesterday = $this->pagedOrder($r, ['created_at' => Carbon::now()->subDay()]);
        $unpaged = Order::withoutGlobalScopes()->findOrFail(
            $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => 'dine_in'] + $this->payload($r))
                ->json('data.id'),
        );

        $res = $this->actingAs($admin)->getJson('/api/dashboard/pickup-board')->assertOk();
        $ids = array_column($res->json('data'), 'id');

        $this->assertSame([$preparing->id, $ready->id, $acked->id, $recentPickup->id], $ids);
        foreach ([$oldPickup, $cancelled, $yesterday, $unpaged] as $hidden) {
            $this->assertNotContains($hidden->id, $ids);
        }

        $byId = collect($res->json('data'))->keyBy('id');
        $this->assertTrue($byId[$ready->id]['call_out']);
        $this->assertFalse($byId[$acked->id]['call_out']);
        $this->assertFalse($byId[$preparing->id]['call_out']);
        $this->assertSame('ORD-'.$ready->id, $byId[$ready->id]['ref']);
        $this->assertArrayNotHasKey('pickup_token', $byId[$ready->id]);
        $this->assertArrayNotHasKey('items', $byId[$ready->id]);
        $this->assertSame(3, $res->json('meta.call_out_minutes'));

        // Ready for less than call_out_minutes: not shouted yet.
        Carbon::setTestNow('2026-11-02 12:00:00');
        $fresh = $this->pagedOrder($r, ['pickup_status' => 'READY', 'ready_at' => Carbon::now()->subMinute()]);
        $row = collect($this->actingAs($admin)->getJson('/api/dashboard/pickup-board')->json('data'))->keyBy('id');
        $this->assertFalse($row[$fresh->id]['call_out']);
    }

    public function test_board_filters_by_branch_and_answers_304_when_unchanged(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $a = $r->branches()->create(['name_en' => 'A', 'supported_order_types' => ['pickup']]);
        $b = $r->branches()->create(['name_en' => 'B', 'supported_order_types' => ['pickup']]);
        $inA = $this->pagedOrder($r, ['branch_id' => $a->id]);
        $this->pagedOrder($r, ['branch_id' => $b->id]);

        $res = $this->actingAs($admin)->getJson("/api/dashboard/pickup-board?branch_id={$a->id}")->assertOk();
        $this->assertSame([$inA->id], array_column($res->json('data'), 'id'));

        $etag = $res->headers->get('ETag');
        $this->assertNotNull($etag);
        $this->actingAs($admin)->getJson("/api/dashboard/pickup-board?branch_id={$a->id}", ['If-None-Match' => $etag])
            ->assertStatus(304);
    }

    public function test_board_is_tenant_scoped(): void
    {
        $mine = $this->tenant();
        $other = $this->tenant();
        $admin = User::factory()->restaurantAdmin($mine->id)->create();
        $this->pagedOrder($other);

        $this->actingAs($admin)->getJson('/api/dashboard/pickup-board')->assertOk()->assertJsonCount(0, 'data');
    }

    // ---- the service's clock rule (BR-9), ahead of the POS endpoint in S5

    public function test_a_supplied_event_time_is_clamped_to_the_orders_life(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r);
        $service = app(GuestPagingService::class);

        Carbon::setTestNow($order->created_at->copy()->addMinutes(10));
        $result = $service->transition($order, PickupStatus::READY, GuestPagingService::SOURCE_POS, null, $order->created_at->copy()->subHour());
        $this->assertTrue($result['applied']);
        $this->assertEquals($order->created_at, $order->fresh()->ready_at);
        $this->assertSame('pos', $order->fresh()->ready_source);

        $future = $service->transition($order, PickupStatus::PICKED_UP, GuestPagingService::SOURCE_POS, null, Carbon::now()->addDay());
        $this->assertTrue($future['applied']);
        $this->assertEquals(Carbon::now(), $order->fresh()->picked_up_at);

        // A delayed READY after PICKED_UP is reported, not refused — the POS
        // outbox treats it as delivered.
        $late = $service->transition($order->fresh(), PickupStatus::READY, GuestPagingService::SOURCE_POS);
        $this->assertFalse($late['applied']);
        $this->assertSame('backwards', $late['reason']);
    }

    // ---- S2: token issuance at intake (AC-2)

    public function test_a_qr_pickup_order_gets_a_tracking_token_only_when_the_flag_is_on(): void
    {
        $r = $this->tenant();
        $res = $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->payload($r))->assertCreated();

        $token = $res->json('data.pickup_token');
        $this->assertMatchesRegularExpression('/^[A-Za-z0-9]{40}$/', $token);
        $this->assertSame($r->fresh()->trackingUrl($token), $res->json('data.tracking_url'));
        $this->assertStringEndsWith('/o/'.$token, $res->json('data.tracking_url'));

        $order = Order::withoutGlobalScopes()->findOrFail($res->json('data.id'));
        $this->assertSame('PREPARING', $order->pickup_status->value);

        // The real page: the intake-issued token resolves, and with no printed
        // number the reference falls back to the order code.
        $this->getJson("/api/public/orders/track/{$token}")->assertOk()
            ->assertJsonPath('data.ref', 'ORD-'.$order->id)
            ->assertJsonPath('data.status', 'PREPARING');

        // Flag off: the same order carries no token and no URL.
        $off = $this->tenant(paging: false);
        $this->postJson("/api/public/restaurants/{$off->slug}/orders", $this->payload($off))
            ->assertCreated()
            ->assertJsonMissingPath('data.pickup_token')
            ->assertJsonMissingPath('data.tracking_url');
    }

    public function test_only_paged_order_types_get_a_token(): void
    {
        $r = $this->tenant();

        $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => 'dine_in'] + $this->payload($r))
            ->assertCreated()->assertJsonMissingPath('data.pickup_token');
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => 'delivery'] + $this->payload($r))
            ->assertCreated()->assertJsonMissingPath('data.pickup_token');
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => null] + $this->payload($r))
            ->assertCreated()->assertJsonMissingPath('data.pickup_token');

        // The owner may widen the set.
        $r->forceFill(['guest_paging_order_types' => ['dine_in', 'pickup']])->save();
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", ['order_type' => 'dine_in'] + $this->payload($r))
            ->assertCreated()->assertJsonStructure(['data' => ['pickup_token']]);
    }

    public function test_a_round_of_a_seated_table_is_never_paged(): void
    {
        $r = $this->tenant();
        app(RestaurantFeatureService::class)->apply($r, [
            'qr_menu' => true, 'system_ordering' => true, 'guest_paging' => true,
            'dine_in' => true, 'table_management' => true,
        ]);
        // Even with dine_in paged, a table session order is served, not collected.
        $r->forceFill(['guest_paging_order_types' => ['dine_in', 'pickup']])->save();

        $branch = new Branch(['name_en' => 'Main']);
        $branch->restaurant_id = $r->id;
        $branch->save();
        $area = new DiningArea(['branch_id' => $branch->id, 'name_en' => 'Indoor']);
        $area->restaurant_id = $r->id;
        $area->save();
        $table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => '12',
            'public_token' => DiningTable::generateToken(), 'qr_generated_at' => now(),
        ]);
        $table->restaurant_id = $r->id;
        $table->branch_id = $branch->id;
        $table->save();
        $session = new MenuSession([
            'branch_id' => $branch->id, 'dining_area_id' => $area->id, 'table_id' => $table->id,
            'language' => 'en', 'session_token' => Str::random(40),
            'started_at' => now(), 'last_activity_at' => now(), 'expires_at' => now()->addHours(4),
        ]);
        $session->restaurant_id = $r->id;
        $session->save();

        $res = $this->postJson("/api/public/restaurants/{$r->slug}/orders", [
            'session_token' => $session->session_token,
        ] + $this->payload($r))->assertCreated();

        $res->assertJsonMissingPath('data.pickup_token');
        $order = Order::withoutGlobalScopes()->findOrFail($res->json('data.id'));
        $this->assertNotNull($order->table_visit_id);
        $this->assertNull($order->pickup_token);
    }

    // ---- S2: the public tracking page (AC-3, BR-4, BR-5, BR-7)

    private function track(string $token, array $headers = [])
    {
        return $this->getJson("/api/public/orders/track/{$token}", $headers);
    }

    public function test_tracking_shows_the_reference_and_state_and_nothing_private(): void
    {
        $r = $this->tenant();
        $r->forceFill(['review_public_url' => 'https://g.page/r/demo/review', 'review_thank_you_en' => 'Thanks!'])->save();
        $order = $this->pagedOrder($r);
        $token = $order->pickup_token;

        $res = $this->track($token)->assertOk();
        $this->assertSame([
            'ref', 'status', 'order_status', 'placed_at', 'ready_at', 'acknowledged_at', 'picked_up_at',
            'order_type', 'call_out', 'restaurant', 'branch', 'review_public_url', 'review_thank_you',
        ], array_keys($res->json('data')));
        $res->assertJsonPath('data.ref', 'ORD-'.$order->id)
            ->assertJsonPath('data.status', 'PREPARING')
            ->assertJsonPath('data.order_status', 'NEW')
            ->assertJsonPath('data.order_type', 'pickup')
            ->assertJsonPath('data.call_out', false)
            ->assertJsonPath('data.review_public_url', null)
            ->assertJsonPath('data.branch', null)
            ->assertJsonMissingPath('data.items')
            ->assertJsonMissingPath('data.total')
            ->assertJsonMissingPath('data.customer_name')
            ->assertJsonMissingPath('data.customer_phone');
        $this->assertSame(['name', 'logo_url', 'brand_color'], array_keys($res->json('data.restaurant')));
        $this->assertStringNotContainsString('Amer', $res->getContent());
        $this->assertStringNotContainsString('+2012', $res->getContent());

        // The review invitation appears only once the food is in hand.
        app(GuestPagingService::class)->transition($order, PickupStatus::PICKED_UP, GuestPagingService::SOURCE_DASHBOARD);
        $this->track($token)->assertOk()
            ->assertJsonPath('data.status', 'PICKED_UP')
            ->assertJsonPath('data.order_status', 'COMPLETED')
            ->assertJsonPath('data.review_public_url', 'https://g.page/r/demo/review')
            ->assertJsonPath('data.review_thank_you', 'Thanks!');
    }

    public function test_tracking_answers_404_for_unknown_expired_or_malformed_tokens_and_403_when_off(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r);

        $this->track(Str::random(40))->assertNotFound();
        $this->track('short')->assertNotFound();
        $this->track(Str::random(39).'!')->assertNotFound();

        // Past the TTL the link stops resolving, with the same answer as unknown.
        Carbon::setTestNow($order->created_at->copy()->addHours(49));
        $this->track($order->pickup_token)->assertNotFound();
        Carbon::setTestNow($order->created_at->copy()->addHours(47));
        $this->track($order->pickup_token)->assertOk();

        // The feature switched off mid-life: the page goes dark.
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true, 'guest_paging' => false]);
        $this->track($order->pickup_token)->assertForbidden();
    }

    public function test_tracking_is_304_when_nothing_moved_and_reflects_cancellation(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r);

        $first = $this->track($order->pickup_token)->assertOk();
        $etag = $first->headers->get('ETag');
        $this->assertNotNull($etag);
        $this->track($order->pickup_token, ['If-None-Match' => $etag])->assertStatus(304);

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED'])->assertOk();
        $this->track($order->pickup_token, ['If-None-Match' => $etag])->assertOk()
            ->assertJsonPath('data.order_status', 'CANCELLED')
            ->assertJsonPath('data.status', 'PREPARING');
    }

    public function test_follow_and_ack_stamp_once_and_ack_needs_ready(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r);
        $t = $order->pickup_token;

        Carbon::setTestNow('2026-11-02 10:00:00');
        $this->postJson("/api/public/orders/track/{$t}/follow")->assertOk();
        Carbon::setTestNow('2026-11-02 10:01:00');
        $this->postJson("/api/public/orders/track/{$t}/follow")->assertOk();
        $this->assertSame('2026-11-02T10:00:00+00:00', $order->fresh()->pickup_followed_at->toIso8601String());

        // Not ready yet: nothing to acknowledge.
        $this->postJson("/api/public/orders/track/{$t}/ack")->assertStatus(422);
        $this->assertNull($order->fresh()->acknowledged_at);

        app(GuestPagingService::class)->transition($order, PickupStatus::READY, GuestPagingService::SOURCE_DASHBOARD);
        Carbon::setTestNow('2026-11-02 10:10:00');
        $this->track($t)->assertOk()->assertJsonPath('data.call_out', true);

        $this->postJson("/api/public/orders/track/{$t}/ack")->assertOk()
            ->assertJsonPath('data.acknowledged_at', '2026-11-02T10:10:00+00:00')
            ->assertJsonPath('data.call_out', false);
        Carbon::setTestNow('2026-11-02 10:12:00');
        $this->postJson("/api/public/orders/track/{$t}/ack")->assertOk()
            ->assertJsonPath('data.acknowledged_at', '2026-11-02T10:10:00+00:00');

        // Unknown token on a write is the same 404 as on a read.
        $this->postJson('/api/public/orders/track/'.Str::random(40).'/ack')->assertNotFound();
    }

    public function test_push_token_can_be_stored_and_removed(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r);
        $t = $order->pickup_token;

        $this->postJson("/api/public/orders/track/{$t}/push-token", ['token' => ''])->assertStatus(422);
        $this->postJson("/api/public/orders/track/{$t}/push-token", ['token' => str_repeat('x', 513)])->assertStatus(422);
        $this->postJson("/api/public/orders/track/{$t}/push-token", ['token' => 'fcm-abc'])->assertNoContent();
        $this->assertSame('fcm-abc', $order->fresh()->pickup_push_token);

        // Never echoed back to the page.
        $this->assertStringNotContainsString('fcm-abc', $this->track($t)->getContent());

        $this->deleteJson("/api/public/orders/track/{$t}/push-token")->assertNoContent();
        $this->assertNull($order->fresh()->pickup_push_token);
    }

    public function test_tracking_localises_the_restaurant_name(): void
    {
        $r = $this->tenant();
        $r->forceFill(['name_en' => 'Al-Hay Coffee', 'name_ar' => 'قهوة الحي'])->save();
        $order = $this->pagedOrder($r);

        $this->track($order->pickup_token, ['X-Locale' => 'ar'])->assertOk()
            ->assertJsonPath('data.restaurant.name', 'قهوة الحي');
        $this->track($order->pickup_token, ['X-Locale' => 'en'])->assertOk()
            ->assertJsonPath('data.restaurant.name', 'Al-Hay Coffee');
    }

    // ---- S2 review follow-ups

    public function test_polling_never_starves_the_diners_own_writes(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r, ['pickup_status' => 'READY', 'ready_at' => Carbon::now()]);
        $t = $order->pickup_token;

        // 30 polls from one address exceed the 20/min write limit — if the
        // buckets were shared, the ack below would be a 429.
        for ($i = 0; $i < 30; $i++) {
            $this->track($t)->assertOk();
        }
        $this->postJson("/api/public/orders/track/{$t}/follow")->assertOk();
        $this->postJson("/api/public/orders/track/{$t}/ack")->assertOk();
        $this->postJson("/api/public/orders/track/{$t}/push-token", ['token' => 'fcm-1'])->assertNoContent();
    }

    public function test_ack_is_refused_on_a_cancelled_order_even_after_ready(): void
    {
        $r = $this->tenant();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $order = $this->pagedOrder($r, ['pickup_status' => 'READY', 'ready_at' => Carbon::now()]);
        $t = $order->pickup_token;

        $this->actingAs($admin)->patchJson("/api/dashboard/orders/{$order->id}/status", ['status' => 'CANCELLED'])->assertOk();

        $this->postJson("/api/public/orders/track/{$t}/ack")->assertStatus(422);
        $this->assertNull($order->fresh()->acknowledged_at);
        $this->track($t)->assertOk()->assertJsonPath('data.order_status', 'CANCELLED');
    }

    public function test_every_write_shares_the_404_and_403_rules_of_the_read(): void
    {
        $r = $this->tenant();
        $order = $this->pagedOrder($r);
        $t = $order->pickup_token;

        Carbon::setTestNow($order->created_at->copy()->addHours(49));
        $this->postJson("/api/public/orders/track/{$t}/follow")->assertNotFound();
        $this->postJson("/api/public/orders/track/{$t}/push-token", ['token' => 'x'])->assertNotFound();
        $this->deleteJson("/api/public/orders/track/{$t}/push-token")->assertNotFound();
        Carbon::setTestNow();

        // A suspended restaurant: the page goes dark the same way as feature-off.
        $r->forceFill(['status' => 'SUSPENDED'])->save();
        $this->track($t)->assertForbidden();
        $this->postJson("/api/public/orders/track/{$t}/follow")->assertForbidden();
    }

    public function test_both_tokens_stay_out_of_the_audit_diff_and_lang_query_works(): void
    {
        $r = $this->tenant();
        $r->forceFill(['name_en' => 'Al-Hay Coffee', 'name_ar' => 'قهوة الحي'])->save();
        $order = $this->pagedOrder($r);

        $excluded = $order->auditExcludedAttributes();
        $this->assertContains('pickup_token', $excluded);
        $this->assertContains('pickup_push_token', $excluded);

        $this->getJson("/api/public/orders/track/{$order->pickup_token}?lang=ar")->assertOk()
            ->assertJsonPath('data.restaurant.name', 'قهوة الحي');
    }
}

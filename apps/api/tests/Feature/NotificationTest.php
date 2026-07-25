<?php

namespace Tests\Feature;

use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class NotificationTest extends TestCase
{
    use RefreshDatabase;

    private function enableSystemOrdering(Restaurant $r): void
    {
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true]);
    }

    private function orderPayload(): array
    {
        return [
            'items' => [['name' => 'Burger', 'qty' => 1, 'options' => [], 'line_total' => 80]],
            'total' => 80,
            'customer_name' => 'Amer',
            'customer_phone' => '+201234567890',
        ];
    }

    public function test_a_new_order_records_a_notification(): void
    {
        $r = Restaurant::factory()->create();
        $this->enableSystemOrdering($r);

        // Terminating callbacks (where the notification is recorded) run during
        // the test request's kernel->terminate, so the row exists afterwards.
        $this->postJson("/api/public/restaurants/{$r->slug}/orders", $this->orderPayload())
            ->assertCreated();

        $this->assertDatabaseHas('notifications', [
            'restaurant_id' => $r->id,
            'type' => 'order.created',
        ]);

        $notification = Notification::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();
        $this->assertSame('/admin/orders', $notification->data['url']);
        $this->assertNull($notification->read_at);
    }

    public function test_a_new_review_records_a_notification(): void
    {
        $r = Restaurant::factory()->create(['slug' => 'reviewery']);
        $r->features()->create(['feature_key' => 'internal_reviews', 'is_enabled' => true]);
        $r->load('features');

        $this->postJson("/api/public/restaurants/{$r->slug}/reviews", ['rating' => 2, 'comment' => 'Cold food'])
            ->assertCreated();

        $this->assertDatabaseHas('notifications', [
            'restaurant_id' => $r->id,
            'type' => 'review.created',
        ]);
    }

    public function test_admin_lists_and_marks_notifications(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->seedNotifications($r->id, 3);

        $this->actingAs($admin)->getJson('/api/dashboard/notifications')
            ->assertOk()
            ->assertJsonCount(3, 'data');

        $this->actingAs($admin)->getJson('/api/dashboard/notifications/unread-count')
            ->assertOk()
            ->assertJsonPath('data.unread', 3);

        $one = Notification::withoutGlobalScopes()->where('restaurant_id', $r->id)->first();
        $this->actingAs($admin)->patchJson("/api/dashboard/notifications/{$one->id}/read")
            ->assertOk()
            ->assertJsonPath('data.read', true);

        $this->actingAs($admin)->getJson('/api/dashboard/notifications/unread-count')
            ->assertJsonPath('data.unread', 2);

        $this->actingAs($admin)->postJson('/api/dashboard/notifications/read-all')
            ->assertOk()
            ->assertJsonPath('data.cleared', 2);

        $this->actingAs($admin)->getJson('/api/dashboard/notifications/unread-count')
            ->assertJsonPath('data.unread', 0);
    }

    public function test_notifications_are_tenant_isolated(): void
    {
        $mine = Restaurant::factory()->create();
        $other = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($mine->id)->create();

        $this->seedNotifications($mine->id, 1);
        $this->seedNotifications($other->id, 1);

        $this->actingAs($admin)->getJson('/api/dashboard/notifications')
            ->assertOk()
            ->assertJsonCount(1, 'data');

        // A foreign notification is unreachable — a 404, never a 403.
        $foreign = Notification::withoutGlobalScopes()->where('restaurant_id', $other->id)->first();
        $this->actingAs($admin)->patchJson("/api/dashboard/notifications/{$foreign->id}/read")
            ->assertNotFound();
    }

    public function test_pulse_reports_counts_and_honours_etag(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();
        $this->enableSystemOrdering($r);
        $r->load('features');

        // Build state directly (no public endpoint / terminating callbacks) so
        // both polls below observe identical state and the ETag stays stable.
        $order = new Order(['items' => [], 'total' => 80, 'status' => 'NEW']);
        $order->restaurant_id = $r->id;
        $order->save();
        $this->seedNotifications($r->id, 1);

        $res = $this->actingAs($admin)->getJson('/api/dashboard/pulse')
            ->assertOk()
            ->assertJsonPath('data.new_orders', 1)
            ->assertJsonPath('data.unread_notifications', 1);

        $etag = $res->headers->get('ETag');
        $this->assertNotEmpty($etag);

        // An unchanged pulse re-hashes to the same ETag → bodyless 304.
        $this->actingAs($admin)
            ->withHeaders(['If-None-Match' => $etag])
            ->getJson('/api/dashboard/pulse')
            ->assertStatus(304);
    }

    public function test_pulse_nulls_counts_for_ungated_features(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // No system_ordering / bill_requests features enabled.
        $this->actingAs($admin)->getJson('/api/dashboard/pulse')
            ->assertOk()
            ->assertJsonPath('data.new_orders', null)
            ->assertJsonPath('data.new_requests', null);
    }

    private function seedNotifications(int $restaurantId, int $count): void
    {
        for ($i = 0; $i < $count; $i++) {
            $n = new Notification([
                'type' => 'order.created',
                'title' => 'New order',
                'body' => 'ORD-'.$i,
                'data' => ['url' => '/admin/orders'],
            ]);
            $n->restaurant_id = $restaurantId;
            $n->save();
        }
    }
}

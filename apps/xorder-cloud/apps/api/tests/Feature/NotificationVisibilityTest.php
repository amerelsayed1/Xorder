<?php

namespace Tests\Feature;

use App\Enums\TenantCapability as Cap;
use App\Models\DeviceToken;
use App\Models\Notification;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\PushService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * A notification carries real business data (an order's code and total, a diner's
 * review, a bill request). Staff must only see the kinds their role can already
 * open, in the feed, the badge counts, the mark-read actions and the web push.
 * The owner sees everything; a kind nobody mapped is hidden from staff.
 */
class NotificationVisibilityTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create();
    }

    /** @param  list<Cap>  $caps */
    private function staff(array $caps): User
    {
        $role = new Role(['name' => 'Scoped '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => Cap::expand(array_map(fn (Cap $c) => $c->value, $caps)),
        ])->save();

        return User::factory()->staff($this->restaurant->id, $role->id)->create();
    }

    private function note(string $type, ?Restaurant $restaurant = null): Notification
    {
        $n = new Notification(['type' => $type, 'title' => $type, 'body' => 'ORD-1 · 36.00 EGP', 'data' => ['url' => '/admin']]);
        $n->restaurant_id = ($restaurant ?? $this->restaurant)->id;
        $n->save();

        return $n;
    }

    private function seedAll(): void
    {
        foreach (['order.created', 'bill_request.created', 'review.created', 'subscription.expiring'] as $type) {
            $this->note($type);
        }
    }

    /** @return list<string> */
    private function feedTypes(User $user): array
    {
        return collect($this->actingAs($user)->getJson('/api/dashboard/notifications')->assertOk()->json('data'))
            ->pluck('type')->sort()->values()->all();
    }

    public function test_each_kind_is_visible_only_to_the_capability_that_opens_it(): void
    {
        $this->seedAll();

        $this->assertSame(['order.created'], $this->feedTypes($this->staff([Cap::ORDERS_VIEW])));
        $this->assertSame(['bill_request.created'], $this->feedTypes($this->staff([Cap::BILLS_VIEW])));
        $this->assertSame(['review.created'], $this->feedTypes($this->staff([Cap::REVIEWS_VIEW])));
    }

    public function test_a_role_with_no_matching_capability_sees_an_empty_feed(): void
    {
        $this->seedAll();

        $this->assertSame([], $this->feedTypes($this->staff([Cap::MENU_VIEW])));
    }

    public function test_the_owner_sees_every_kind_including_subscription_notices(): void
    {
        $this->seedAll();
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();

        $this->assertSame(
            ['bill_request.created', 'order.created', 'review.created', 'subscription.expiring'],
            $this->feedTypes($owner),
        );
    }

    public function test_an_unmapped_kind_is_hidden_from_staff_and_shown_to_the_owner(): void
    {
        $this->note('something.new');
        $staff = $this->staff([Cap::ORDERS_VIEW, Cap::BILLS_VIEW, Cap::REVIEWS_VIEW]);
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();

        $this->assertSame([], $this->feedTypes($staff));
        $this->assertSame(['something.new'], $this->feedTypes($owner));
    }

    public function test_the_unread_badge_and_pulse_count_only_what_the_user_may_see(): void
    {
        $this->seedAll();
        $staff = $this->staff([Cap::REVIEWS_VIEW]);

        $this->actingAs($staff)->getJson('/api/dashboard/notifications/unread-count')
            ->assertOk()->assertJsonPath('data.unread', 1);

        $pulse = $this->actingAs($staff)->getJson('/api/dashboard/pulse')->assertOk();
        $pulse->assertJsonPath('data.unread_notifications', 1);

        $nobody = $this->staff([Cap::MENU_VIEW]);
        $this->actingAs($nobody)->getJson('/api/dashboard/notifications/unread-count')
            ->assertOk()->assertJsonPath('data.unread', 0);
        $this->actingAs($nobody)->getJson('/api/dashboard/pulse')
            ->assertOk()->assertJsonPath('data.unread_notifications', 0);
    }

    public function test_the_latest_id_does_not_reveal_hidden_notifications(): void
    {
        $visible = $this->note('review.created');
        $this->note('order.created'); // newer, but hidden from a reviews-only role

        $this->actingAs($this->staff([Cap::REVIEWS_VIEW]))->getJson('/api/dashboard/pulse')
            ->assertOk()->assertJsonPath('data.latest_notification_id', $visible->id);
    }

    public function test_a_hidden_notification_cannot_be_marked_read_and_looks_like_it_does_not_exist(): void
    {
        $hidden = $this->note('order.created');

        $this->actingAs($this->staff([Cap::REVIEWS_VIEW]))
            ->patchJson("/api/dashboard/notifications/{$hidden->id}/read")
            ->assertNotFound();

        $this->assertNull($hidden->fresh()->read_at);
    }

    public function test_a_visible_notification_can_be_marked_read(): void
    {
        $mine = $this->note('review.created');

        $this->actingAs($this->staff([Cap::REVIEWS_VIEW]))
            ->patchJson("/api/dashboard/notifications/{$mine->id}/read")
            ->assertOk();

        $this->assertNotNull($mine->fresh()->read_at);
    }

    public function test_mark_all_read_clears_only_what_the_user_may_see(): void
    {
        $order = $this->note('order.created');
        $review = $this->note('review.created');

        $this->actingAs($this->staff([Cap::REVIEWS_VIEW]))
            ->postJson('/api/dashboard/notifications/read-all')
            ->assertOk()->assertJsonPath('data.cleared', 1);

        $this->assertNull($order->fresh()->read_at, 'an order alert hidden from this role must stay unread for those who can see it');
        $this->assertNotNull($review->fresh()->read_at);
    }

    public function test_another_restaurants_notifications_stay_invisible_even_to_its_owner(): void
    {
        $other = Restaurant::factory()->create();
        $this->note('order.created', $other);
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();

        $this->assertSame([], $this->feedTypes($owner));
    }

    public function test_web_push_goes_only_to_devices_whose_user_may_see_that_kind(): void
    {
        $orders = $this->staff([Cap::ORDERS_VIEW]);
        $reviews = $this->staff([Cap::REVIEWS_VIEW]);
        $nobody = $this->staff([Cap::MENU_VIEW]);
        $owner = User::factory()->restaurantAdmin($this->restaurant->id)->create();

        foreach ([$orders, $reviews, $nobody, $owner] as $i => $user) {
            DeviceToken::create([
                'user_id' => $user->id,
                'restaurant_id' => $this->restaurant->id,
                'token' => "token-{$i}",
                'platform' => 'web',
            ]);
        }

        $push = app(PushService::class);

        $this->assertEqualsCanonicalizing(['token-0', 'token-3'], $push->tokensFor($this->restaurant->id, 'order.created'));
        $this->assertEqualsCanonicalizing(['token-1', 'token-3'], $push->tokensFor($this->restaurant->id, 'review.created'));
        $this->assertSame(['token-3'], $push->tokensFor($this->restaurant->id, 'subscription.expiring'));
    }
}

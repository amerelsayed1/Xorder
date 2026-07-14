<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use App\Models\User;
use App\Notifications\SubscriptionExpiringSoon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class SubscriptionLifecycleTest extends TestCase
{
    use RefreshDatabase;

    public function test_ended_subscriptions_are_expired(): void
    {
        $ended = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->subDay()->toDateString(),
        ]);
        $running = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addMonth()->toDateString(),
        ]);

        $this->artisan('subscriptions:process')->assertSuccessful();

        $this->assertSame(SubscriptionStatus::EXPIRED, $ended->fresh()->subscription_status);
        $this->assertSame(SubscriptionStatus::ACTIVE, $running->fresh()->subscription_status);
    }

    public function test_admins_are_warned_seven_days_before_expiry(): void
    {
        Notification::fake();

        $r = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(7)->toDateString(),
        ]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // A restaurant further out gets no warning.
        $far = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(20)->toDateString(),
        ]);
        $farAdmin = User::factory()->restaurantAdmin($far->id)->create();

        $this->artisan('subscriptions:process')->assertSuccessful();

        Notification::assertSentTo($admin, SubscriptionExpiringSoon::class);
        Notification::assertNotSentTo($farAdmin, SubscriptionExpiringSoon::class);
    }

    public function test_restaurants_without_end_date_are_untouched(): void
    {
        $r = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => null,
        ]);

        $this->artisan('subscriptions:process')->assertSuccessful();

        $this->assertSame(SubscriptionStatus::ACTIVE, $r->fresh()->subscription_status);
    }
}

<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SubscriptionAndStatusTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_change_status_and_subscription(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/status", ['status' => 'SUSPENDED'])
            ->assertOk();
        $this->assertSame(RestaurantStatus::SUSPENDED, $r->fresh()->status);

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", ['subscription_status' => 'EXPIRED'])
            ->assertOk();
        $this->assertSame(SubscriptionStatus::EXPIRED, $r->fresh()->subscription_status);
    }

    public function test_expired_subscription_blocks_dashboard_writes_but_allows_reads(): void
    {
        config(['platform.subscription.enforce_dashboard_writes' => true]);

        $r = Restaurant::factory()->create(['subscription_status' => SubscriptionStatus::EXPIRED]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // Read still works
        $this->actingAs($admin)->getJson('/api/dashboard/categories')->assertOk();

        // Write is blocked by the subscription.writable middleware
        $this->actingAs($admin)->postJson('/api/dashboard/categories', ['name_en' => 'X'])
            ->assertForbidden();
    }

    public function test_suspended_restaurant_blocks_dashboard_writes(): void
    {
        $r = Restaurant::factory()->suspended()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->postJson('/api/dashboard/categories', ['name_en' => 'X'])
            ->assertForbidden();
    }

    public function test_active_subscription_requires_start_and_end_dates(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", ['subscription_status' => 'ACTIVE'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['subscription_start_date', 'subscription_end_date']);

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", [
            'subscription_status' => 'ACTIVE',
            'subscription_start_date' => now()->toDateString(),
            'subscription_end_date' => now()->addMonth()->toDateString(),
        ])->assertOk();
        $this->assertSame(SubscriptionStatus::ACTIVE, $r->fresh()->subscription_status);
    }

    public function test_trial_subscription_requires_end_date_only(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $r = Restaurant::factory()->create();

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", ['subscription_status' => 'TRIAL'])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['subscription_end_date'])
            ->assertJsonMissingValidationErrors(['subscription_start_date']);

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", [
            'subscription_status' => 'TRIAL',
            'subscription_end_date' => now()->addDays(14)->toDateString(),
        ])->assertOk();
    }

    public function test_restaurant_admin_cannot_change_subscription(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->patchJson("/api/admin/restaurants/{$r->id}/subscription", ['subscription_status' => 'ACTIVE'])
            ->assertForbidden();
    }
}

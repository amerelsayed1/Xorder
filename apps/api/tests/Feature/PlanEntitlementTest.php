<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\PlanEntitlementService;
use App\Services\RestaurantFeatureService;
use App\Services\RestaurantProvisioningService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

/**
 * The subscription plan strictly decides which capabilities a restaurant gets:
 * its feature flags are derived from the plan's feature_keys, and the gated
 * order-management / customer-tracking surfaces appear only when the plan
 * grants them.
 */
class PlanEntitlementTest extends TestCase
{
    use RefreshDatabase;

    private function whatsappPlan(): Plan
    {
        return Plan::create([
            'name' => 'Menu Plus',
            'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'whatsapp_ordering', 'pickup', 'delivery'],
        ]);
    }

    private function proPlan(): Plan
    {
        return Plan::create([
            'name' => 'Restaurant Pro',
            'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'system_ordering', 'customer_tracking', 'bill_requests'],
        ]);
    }

    public function test_provision_derives_features_from_the_assigned_plan(): void
    {
        Notification::fake();
        $this->proPlan();

        $result = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'Pro Co', 'slug' => 'pro-co', 'default_language' => 'en', 'currency' => 'EGP', 'subscription_plan' => 'Restaurant Pro'],
            ['name' => 'Owner', 'email' => 'owner@pro.test'],
        );

        $r = $result['restaurant'];
        $this->assertTrue($r->hasFeature(Feature::SYSTEM_ORDERING));
        $this->assertTrue($r->hasFeature(Feature::CUSTOMER_TRACKING));
        // Prerequisites expand: bill_requests → table_management → dine_in.
        $this->assertTrue($r->hasFeature(Feature::TABLE_MANAGEMENT));
        $this->assertTrue($r->hasFeature(Feature::DINE_IN));
        // Not granted by this plan.
        $this->assertFalse($r->hasFeature(Feature::PRODUCT_ANALYTICS));
    }

    public function test_whatsapp_plan_grants_no_system_ordering_or_tracking(): void
    {
        Notification::fake();
        $this->whatsappPlan();

        $result = app(RestaurantProvisioningService::class)->provision(
            ['name_en' => 'WA Co', 'slug' => 'wa-co', 'default_language' => 'en', 'currency' => 'EGP', 'subscription_plan' => 'Menu Plus'],
            ['name' => 'Owner', 'email' => 'owner@wa.test'],
        );

        $r = $result['restaurant'];
        $this->assertTrue($r->hasFeature(Feature::WHATSAPP_ORDERING));
        $this->assertFalse($r->hasFeature(Feature::SYSTEM_ORDERING));
        $this->assertFalse($r->hasFeature(Feature::CUSTOMER_TRACKING));
    }

    public function test_customer_tracking_no_longer_requires_system_ordering(): void
    {
        // Customers are captured on every ordering type (system orders and
        // WhatsApp checkout alike), so the directory has no prerequisite.
        $resolved = Feature::resolve(['customer_tracking' => true]);

        $this->assertTrue($resolved['customer_tracking']);
        $this->assertFalse($resolved['system_ordering']);
    }

    public function test_orders_route_requires_system_ordering(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // WhatsApp-only: no system_ordering → order management is hidden.
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'whatsapp_ordering' => true]);
        $this->actingAs($admin)->getJson('/api/dashboard/orders')->assertStatus(403);

        // Grant system_ordering → the queue opens up. A fresh admin instance
        // avoids the cached restaurant.features relation from the first request.
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'system_ordering' => true]);
        $this->actingAs($admin->fresh())->getJson('/api/dashboard/orders')->assertOk();
    }

    public function test_customers_route_available_on_every_plan(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        // Even a WhatsApp-only plan (no system_ordering, no customer_tracking)
        // can reach the customer directory now.
        app(RestaurantFeatureService::class)->apply($r, ['qr_menu' => true, 'whatsapp_ordering' => true]);
        $this->actingAs($admin)->getJson('/api/dashboard/customers')->assertOk();
    }

    public function test_changing_the_plan_via_subscription_endpoint_re_derives_features(): void
    {
        $sa = User::factory()->superAdmin()->create();
        $this->proPlan();
        $r = Restaurant::factory()->create();
        app(RestaurantFeatureService::class)->apply($r, Feature::defaultSet());
        $this->assertFalse($r->fresh()->hasFeature(Feature::SYSTEM_ORDERING));

        $this->actingAs($sa)->patchJson("/api/admin/restaurants/{$r->id}/subscription", [
            'subscription_status' => 'ACTIVE',
            'subscription_plan' => 'Restaurant Pro',
            'subscription_start_date' => '2026-01-01',
            'subscription_end_date' => '2026-12-31',
        ])->assertOk();

        $r->refresh()->load('features');
        $this->assertTrue($r->hasFeature(Feature::SYSTEM_ORDERING));
        $this->assertTrue($r->hasFeature(Feature::CUSTOMER_TRACKING));
    }

    public function test_super_admin_can_store_plan_entitlements_and_invalid_keys_are_rejected(): void
    {
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson('/api/admin/plans', [
            'name' => 'Custom', 'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'system_ordering'],
        ])->assertCreated()
            ->assertJsonPath('data.feature_keys.1', 'system_ordering');

        $this->actingAs($sa)->postJson('/api/admin/plans', [
            'name' => 'Bad', 'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'not_a_feature'],
        ])->assertStatus(422)->assertJsonValidationErrors('feature_keys.1');
    }

    public function test_sync_is_a_no_op_for_a_plan_without_entitlements(): void
    {
        // Legacy plan with no feature_keys must not wipe an existing feature set.
        Plan::create(['name' => 'Legacy', 'currency' => 'EGP']);
        $r = Restaurant::factory()->create(['subscription_plan' => 'Legacy']);
        app(RestaurantFeatureService::class)->apply($r, Feature::defaultSet());

        app(PlanEntitlementService::class)->sync($r->fresh());

        $this->assertTrue($r->fresh()->hasFeature(Feature::QR_MENU));
    }
}

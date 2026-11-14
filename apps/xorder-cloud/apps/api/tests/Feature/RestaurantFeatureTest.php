<?php

namespace Tests\Feature;

use App\Enums\Feature;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\User;
use App\Services\RestaurantFeatureService;
use App\Services\RestaurantProvisioningService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Notification;
use Tests\TestCase;

class RestaurantFeatureTest extends TestCase
{
    use RefreshDatabase;

    private function provisioner(): RestaurantProvisioningService
    {
        return app(RestaurantProvisioningService::class);
    }

    private function restaurantData(string $slug): array
    {
        return ['name_en' => 'Feat', 'slug' => $slug, 'default_language' => 'en', 'currency' => 'EGP'];
    }

    private function adminData(string $email): array
    {
        return ['name' => 'Owner', 'email' => $email];
    }

    public function test_resolve_pulls_in_prerequisite_features(): void
    {
        $resolved = Feature::resolve(['bill_requests' => true]);

        $this->assertTrue($resolved['bill_requests']);
        // Bill requests require table management (FR-FEATURES-005/006).
        $this->assertTrue($resolved['table_management']);
        $this->assertFalse($resolved['internal_reviews']);
    }

    public function test_provision_applies_default_feature_set_when_none_requested(): void
    {
        Notification::fake();

        $result = $this->provisioner()->provision(
            $this->restaurantData('feat-default'),
            $this->adminData('default@feat.test'),
        );

        $restaurant = $result['restaurant'];

        $this->assertTrue($restaurant->hasFeature(Feature::QR_MENU));
        $this->assertTrue($restaurant->hasFeature(Feature::WHATSAPP_ORDERING));
        $this->assertFalse($restaurant->hasFeature(Feature::TABLE_MANAGEMENT));
        $this->assertFalse($restaurant->hasFeature(Feature::BILL_REQUESTS));

        // Every feature is materialised as exactly one row per restaurant.
        $this->assertDatabaseCount('restaurant_features', count(Feature::cases()));
    }

    public function test_provision_persists_requested_features_and_prerequisites(): void
    {
        Notification::fake();

        $result = $this->provisioner()->provision(
            $this->restaurantData('feat-bill'),
            $this->adminData('bill@feat.test'),
            features: ['bill_requests' => true, 'internal_reviews' => true],
        );

        $restaurant = $result['restaurant']->fresh();

        $this->assertTrue($restaurant->hasFeature(Feature::BILL_REQUESTS));
        $this->assertTrue($restaurant->hasFeature(Feature::TABLE_MANAGEMENT)); // auto-enabled
        $this->assertTrue($restaurant->hasFeature(Feature::INTERNAL_REVIEWS));
        $this->assertFalse($restaurant->hasFeature(Feature::PRODUCT_ANALYTICS));

        $this->assertDatabaseHas('restaurant_features', [
            'restaurant_id' => $restaurant->id,
            'feature_key' => 'table_management',
            'is_enabled' => true,
        ]);
    }

    public function test_provision_creates_first_branch_when_given(): void
    {
        Notification::fake();

        $result = $this->provisioner()->provision(
            $this->restaurantData('feat-branch'),
            $this->adminData('branch@feat.test'),
            branchData: [
                'name_en' => 'Main Branch',
                'code' => 'B1',
                'city' => 'Cairo',
                'supported_order_types' => ['dine_in', 'pickup'],
            ],
        );

        $branch = $result['restaurant']->branches()->first();

        $this->assertNotNull($branch);
        $this->assertSame('Main Branch', $branch->name_en);
        $this->assertSame('B1', $branch->code);
        $this->assertSame(['dine_in', 'pickup'], $branch->supported_order_types);
        $this->assertSame($result['restaurant']->id, $branch->restaurant_id);
    }

    public function test_provision_skips_branch_when_none_given(): void
    {
        Notification::fake();

        $result = $this->provisioner()->provision(
            $this->restaurantData('feat-nobranch'),
            $this->adminData('nobranch@feat.test'),
        );

        $this->assertSame(0, $result['restaurant']->branches()->count());
    }

    public function test_super_admin_created_client_derives_features_strictly_from_its_plan(): void
    {
        Notification::fake();
        $sa = User::factory()->superAdmin()->create();

        // The plan is the single source of truth for capabilities.
        Plan::create([
            'name' => 'Starter',
            'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'bill_requests'],
        ]);

        $this->actingAs($sa)->postJson('/api/admin/restaurants', [
            'name_en' => 'Wizard Co', 'slug' => 'wizard-co',
            'default_language' => 'en', 'currency' => 'EGP',
            'subscription_plan' => 'Starter',
            'admin' => ['name' => 'Owner', 'username' => 'wizardowner', 'email' => 'owner@wizard.test'],
            // A conflicting flag map is ignored — creation respects the plan.
            'features' => ['product_analytics' => true, 'whatsapp_ordering' => true],
            'branch' => [
                'name_en' => 'Downtown', 'code' => 'DT1',
                'supported_order_types' => ['dine_in', 'delivery'],
            ],
        ])->assertCreated();

        $restaurant = Restaurant::where('slug', 'wizard-co')->firstOrFail();

        // Granted: the plan's entitlements (bill_requests auto-expands its
        // table_management prerequisite).
        $this->assertTrue($restaurant->hasFeature(Feature::QR_MENU));
        $this->assertTrue($restaurant->hasFeature(Feature::BILL_REQUESTS));
        $this->assertTrue($restaurant->hasFeature(Feature::TABLE_MANAGEMENT));
        // NOT granted: the hand-passed flags the plan doesn't include.
        $this->assertFalse($restaurant->hasFeature(Feature::PRODUCT_ANALYTICS));
        $this->assertFalse($restaurant->hasFeature(Feature::WHATSAPP_ORDERING));

        $branch = $restaurant->branches()->firstOrFail();
        $this->assertSame('Downtown', $branch->name_en);
        $this->assertSame(['dine_in', 'delivery'], $branch->supported_order_types);
    }

    public function test_changing_a_clients_plan_re_derives_its_features(): void
    {
        Notification::fake();
        $sa = User::factory()->superAdmin()->create();

        // The plan strictly decides features: hand-passed flags are ignored and
        // the restaurant's capabilities are re-derived from the assigned plan.
        Plan::create([
            'name' => 'Pro',
            'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'whatsapp_ordering', 'table_management'],
        ]);

        $r = Restaurant::factory()->create(['slug' => 'edit-feat']);
        app(RestaurantFeatureService::class)->apply($r, Feature::defaultSet());
        $this->assertFalse($r->fresh()->hasFeature(Feature::TABLE_MANAGEMENT));

        $this->actingAs($sa)->putJson("/api/admin/restaurants/{$r->id}", [
            'subscription_plan' => 'Pro',
            // Even a bogus flag map is ignored — the plan is authoritative.
            'features' => ['product_analytics' => true],
        ])->assertOk();

        $r->refresh()->load('features');
        $this->assertTrue($r->hasFeature(Feature::TABLE_MANAGEMENT));
        $this->assertTrue($r->hasFeature(Feature::DINE_IN)); // prerequisite auto-enabled
        $this->assertTrue($r->hasFeature(Feature::QR_MENU));
        $this->assertFalse($r->hasFeature(Feature::DELIVERY)); // not in the plan
        $this->assertFalse($r->hasFeature(Feature::PRODUCT_ANALYTICS)); // hand-passed flag ignored
    }

    public function test_self_serve_signup_provisions_default_feature_flags(): void
    {
        Notification::fake();
        config(['platform.self_serve_signup' => true]);

        $this->postJson('/api/public/signup', [
            'restaurant_name' => 'Signup Cafe',
            'name' => 'Amer',
            'email' => 'signup@feat.test',
        ])->assertCreated();

        $restaurant = Restaurant::where('name_en', 'Signup Cafe')->firstOrFail();

        // Both front doors go through the same provisioning core, so a self-serve
        // client is born with the same default flags a wizard client would be.
        $this->assertTrue($restaurant->hasFeature(Feature::QR_MENU));
        $this->assertFalse($restaurant->hasFeature(Feature::TABLE_MANAGEMENT));
    }
}

<?php

namespace Tests\Feature;

use App\Enums\SubscriptionStatus;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class InsightsTest extends TestCase
{
    use RefreshDatabase;

    /*
    |------------------------------------------------------------------
    | Super Admin platform insights
    |------------------------------------------------------------------
    */

    public function test_admin_insights_require_super_admin(): void
    {
        $r = Restaurant::factory()->create();
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/admin/insights')->assertForbidden();
    }

    public function test_admin_insights_are_unreachable_when_unauthenticated(): void
    {
        $this->getJson('/api/admin/insights')->assertUnauthorized();
    }

    public function test_admin_insights_aggregate_across_all_tenants(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        $a = Restaurant::factory()->create(['status' => 'ACTIVE']);
        $b = Restaurant::factory()->suspended()->create();
        Restaurant::factory()->create(); // empty restaurant, no categories/items

        $cat = Category::factory()->for($a)->create();
        MenuItem::factory()->count(3)->for($a)->for($cat)->create();
        MenuItem::factory()->for($b)->for(Category::factory()->for($b))->create();

        // Restaurant admins should be counted; super admin excluded.
        User::factory()->restaurantAdmin($a->id)->create();

        $this->actingAs($superAdmin)->getJson('/api/admin/insights')
            ->assertOk()
            ->assertJsonPath('data.restaurants.total', 3)
            ->assertJsonPath('data.restaurants.by_status.ACTIVE', 2) // a + empty default ACTIVE
            ->assertJsonPath('data.restaurants.by_status.SUSPENDED', 1)
            ->assertJsonPath('data.content.total_menu_items', 4)
            ->assertJsonPath('data.content.restaurant_admins', 1)
            ->assertJsonPath('data.needs_attention.restaurants_without_menu_items', 1)
            ->assertJsonStructure([
                'data' => [
                    'restaurants' => ['total', 'by_status', 'new_last_7_days', 'new_last_30_days'],
                    'subscriptions' => ['by_status', 'expiring_in_7_days', 'expiring_in_30_days', 'past_end_date'],
                    'content' => ['total_categories', 'total_menu_items', 'available_menu_items', 'restaurant_admins'],
                    'needs_attention',
                    'top_restaurants',
                    'recent_restaurants',
                ],
            ]);
    }

    public function test_admin_insights_flag_subscriptions_expiring_within_seven_days(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(3)->toDateString(),
        ]);
        Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(20)->toDateString(),
        ]);

        $this->actingAs($superAdmin)->getJson('/api/admin/insights')
            ->assertOk()
            ->assertJsonPath('data.subscriptions.expiring_in_7_days', 1)
            ->assertJsonPath('data.subscriptions.expiring_in_30_days', 2);
    }

    /*
    |------------------------------------------------------------------
    | Restaurant Admin menu-health insights
    |------------------------------------------------------------------
    */

    public function test_dashboard_insights_require_restaurant_admin(): void
    {
        $superAdmin = User::factory()->superAdmin()->create();

        $this->actingAs($superAdmin)->getJson('/api/dashboard/insights')->assertForbidden();
    }

    public function test_dashboard_insights_are_tenant_scoped(): void
    {
        $mine = Restaurant::factory()->create();
        $theirs = Restaurant::factory()->create();

        $myCat = Category::factory()->for($mine)->create();
        MenuItem::factory()->count(2)->for($mine)->for($myCat)->create(['is_available' => true]);
        MenuItem::factory()->for($mine)->for($myCat)->unavailable()->create();

        // Another tenant's data must not leak into the totals.
        MenuItem::factory()->count(5)->for($theirs)->for(Category::factory()->for($theirs))->create();

        $admin = User::factory()->restaurantAdmin($mine->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()
            ->assertJsonPath('data.menu.total_items', 3)
            ->assertJsonPath('data.menu.available_items', 2)
            ->assertJsonPath('data.menu.unavailable_items', 1);
    }

    public function test_dashboard_insights_surface_empty_active_categories(): void
    {
        $r = Restaurant::factory()->create();
        $filled = Category::factory()->for($r)->create(['name_en' => 'Drinks']);
        MenuItem::factory()->for($r)->for($filled)->create();
        Category::factory()->for($r)->create(['name_en' => 'Desserts']); // active, no items

        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $response = $this->actingAs($admin)->getJson('/api/dashboard/insights')->assertOk();

        $issues = collect($response->json('data.needs_attention'));
        $empty = $issues->firstWhere('key', 'empty_active_categories');

        $this->assertNotNull($empty, 'Expected an empty_active_categories issue.');
        $this->assertSame(1, $empty['count']);
        $this->assertContains('Desserts', $empty['sample']);
    }

    public function test_dashboard_insights_report_subscription_days_remaining(): void
    {
        $r = Restaurant::factory()->create([
            'subscription_status' => SubscriptionStatus::ACTIVE,
            'subscription_end_date' => now()->addDays(10)->toDateString(),
        ]);
        $admin = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($admin)->getJson('/api/dashboard/insights')
            ->assertOk()
            ->assertJsonPath('data.subscription.days_remaining', 10)
            ->assertJsonPath('data.subscription.writable', true);
    }
}

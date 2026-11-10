<?php

namespace Tests\Feature;

use App\Models\Category;
use App\Models\LandingContent;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

/**
 * GET /api/dashboard/plan — the restaurant's "My plan" page.
 */
class MyPlanTest extends TestCase
{
    use RefreshDatabase;

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_it_shows_the_current_plan_usage_and_the_plans_on_offer(): void
    {
        Carbon::setTestNow('2026-11-10 09:00:00');
        $starter = Plan::create(['name' => 'Starter', 'price' => 0, 'currency' => 'EGP', 'max_items' => 20, 'max_categories' => 5, 'max_branches' => 1, 'max_staff' => 2, 'feature_keys' => ['qr_menu'], 'sort_order' => 1]);
        Plan::create(['name' => 'Pro', 'price' => 499, 'currency' => 'EGP', 'max_items' => null, 'is_recommended' => true, 'feature_keys' => ['qr_menu', 'system_ordering'], 'sort_order' => 2]);
        Plan::create(['name' => 'Retired', 'price' => 99, 'currency' => 'EGP', 'is_active' => false]);

        $r = Restaurant::factory()->create([
            'subscription_plan' => 'Starter',
            'subscription_status' => 'TRIAL',
            'subscription_start_date' => '2026-11-01',
            'subscription_end_date' => '2026-11-15',
            'timezone' => 'Africa/Cairo',
        ]);
        $owner = User::factory()->restaurantAdmin($r->id)->create();
        $category = Category::factory()->for($r)->create();
        MenuItem::factory()->count(3)->for($r)->for($category)->create();

        $res = $this->actingAs($owner)->getJson('/api/dashboard/plan')->assertOk();

        $res->assertJsonPath('data.plan.name', 'Starter')
            ->assertJsonPath('data.plan.price', 0)
            ->assertJsonPath('data.subscription.status', 'TRIAL')
            ->assertJsonPath('data.subscription.days_left', 5);

        $usage = collect($res->json('data.usage'))->keyBy('key');
        $this->assertSame(['used' => 3, 'max' => 20], ['used' => $usage['items']['used'], 'max' => $usage['items']['max']]);
        $this->assertSame(1, $usage['categories']['used']);
        $this->assertSame(2, $usage['staff']['max']);
        $this->assertArrayNotHasKey('terminals', $usage->all(), 'no POS, no seat meter');

        // Only active plans are offered, in catalogue order, with the current one marked.
        $plans = collect($res->json('data.plans'));
        $this->assertSame(['Starter', 'Pro'], $plans->pluck('name')->all());
        $this->assertTrue($plans[0]['current']);
        $this->assertFalse($plans[1]['current']);
        $this->assertNull($plans[1]['limits']['items'], 'null means unlimited');
        $this->assertSame($starter->id, $res->json('data.plan.id'));
    }

    public function test_a_bespoke_plan_name_still_shows_with_no_limits(): void
    {
        $r = Restaurant::factory()->create(['subscription_plan' => 'Custom deal for Al Waha']);
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $res = $this->actingAs($owner)->getJson('/api/dashboard/plan')->assertOk()
            ->assertJsonPath('data.plan', null)
            ->assertJsonPath('data.plan_name', 'Custom deal for Al Waha');
        $this->assertTrue(collect($res->json('data.usage'))->every(fn ($m) => $m['max'] === null));
    }

    public function test_till_seats_follow_the_licence_like_provisioning_does(): void
    {
        Plan::create(['name' => 'Pos', 'max_terminals' => 2]);
        $r = Restaurant::factory()->create(['subscription_plan' => 'Pos']);
        $r->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $terminals = collect($this->actingAs($owner)->getJson('/api/dashboard/plan')->assertOk()->json('data.usage'))
            ->firstWhere('key', 'terminals');
        $this->assertSame(['key' => 'terminals', 'used' => 0, 'max' => 2], $terminals);
    }

    public function test_the_upgrade_contact_comes_from_the_landing_cms(): void
    {
        $content = LandingContent::current();
        $data = $content->content;
        $data['whatsapp']['number'] = '+20 100 123 4567';
        $content->forceFill(['content' => $data])->save();

        $r = Restaurant::factory()->create();
        $owner = User::factory()->restaurantAdmin($r->id)->create();

        $this->actingAs($owner)->getJson('/api/dashboard/plan')->assertOk()
            ->assertJsonPath('data.support_whatsapp', '201001234567');
    }

    public function test_usage_is_counted_for_this_restaurant_only(): void
    {
        $mine = Restaurant::factory()->create();
        $other = Restaurant::factory()->create();
        MenuItem::factory()->count(4)->for($other)->for(Category::factory()->for($other)->create())->create();
        $owner = User::factory()->restaurantAdmin($mine->id)->create();

        $usage = collect($this->actingAs($owner)->getJson('/api/dashboard/plan')->assertOk()->json('data.usage'))->keyBy('key');
        $this->assertSame(0, $usage['items']['used']);
        $this->assertSame(0, $usage['categories']['used']);
    }

    public function test_it_needs_the_settings_view_capability(): void
    {
        $r = Restaurant::factory()->create();
        $role = new Role(['name' => 'Cook']);
        $role->forceFill(['restaurant_id' => $r->id, 'capabilities' => ['menu.view']])->save();
        $staff = User::factory()->staff($r->id, $role->id)->create();

        $this->actingAs($staff)->getJson('/api/dashboard/plan')->assertForbidden();
    }

    public function test_it_needs_a_signed_in_user(): void
    {
        $this->getJson('/api/dashboard/plan')->assertUnauthorized();
    }
}

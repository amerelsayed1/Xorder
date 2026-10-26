<?php

namespace Tests\Feature;

use App\Enums\TenantCapability;
use App\Models\Branch;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\OrderTypeEntitlements;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * XORD-002 (cloud half) — which order types a branch offers.
 *
 * Switching one on needs the subscription to include it; at least one stays on;
 * only people holding pos.settings.order_types.manage may change the list; and
 * a change reaches the tills through pos_config_version.
 */
class BranchOrderTypesTest extends TestCase
{
    use RefreshDatabase;

    private function tenant(array $features): Restaurant
    {
        $restaurant = Restaurant::factory()->create();
        foreach ($features as $key) {
            $restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }

        return $restaurant;
    }

    private function branch(Restaurant $restaurant, array $types = []): Branch
    {
        return $restaurant->branches()->create(['name_en' => 'Main', 'supported_order_types' => $types]);
    }

    private function staffWith(Restaurant $restaurant, array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $restaurant->id,
            'capabilities' => TenantCapability::expand($capabilities),
            'is_system' => false,
        ])->save();

        return User::factory()->staff($restaurant->id, $role->id)->create();
    }

    private function save(User $user, Branch $branch, array $body)
    {
        return $this->actingAs($user)->putJson("/api/dashboard/branches/{$branch->id}", $body);
    }

    public function test_the_owner_switches_on_what_the_subscription_includes(): void
    {
        $restaurant = $this->tenant(['dine_in', 'delivery']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant);

        $this->save($owner, $branch, ['supported_order_types' => ['delivery', 'dine_in']])->assertOk();

        $this->assertSame(['dine_in', 'delivery'], $branch->fresh()->supported_order_types);
    }

    public function test_a_type_the_subscription_lacks_cannot_be_switched_on(): void
    {
        $restaurant = $this->tenant(['dine_in']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant, ['dine_in']);

        $this->save($owner, $branch, ['supported_order_types' => ['dine_in', 'delivery']])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('supported_order_types');

        $this->assertSame(['dine_in'], $branch->fresh()->supported_order_types);
    }

    public function test_pickup_is_stored_as_takeaway_and_follows_the_pickup_flag(): void
    {
        $restaurant = $this->tenant(['pickup']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant);

        $this->save($owner, $branch, ['supported_order_types' => ['pickup']])->assertOk();

        $this->assertSame(['takeaway'], $branch->fresh()->supported_order_types);
    }

    public function test_drive_thru_follows_the_pos_flag(): void
    {
        $withPos = $this->tenant(['pos']);
        $this->save(User::factory()->restaurantAdmin($withPos->id)->create(), $this->branch($withPos), ['supported_order_types' => ['drive_thru']])->assertOk();

        $without = $this->tenant(['dine_in']);
        $this->save(User::factory()->restaurantAdmin($without->id)->create(), $this->branch($without), ['supported_order_types' => ['drive_thru']])
            ->assertUnprocessable();
    }

    public function test_at_least_one_type_must_stay_on(): void
    {
        $restaurant = $this->tenant(['dine_in']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant, ['dine_in']);

        $this->save($owner, $branch, ['supported_order_types' => []])
            ->assertUnprocessable()
            ->assertJsonValidationErrors('supported_order_types');

        $this->assertSame(['dine_in'], $branch->fresh()->supported_order_types);
    }

    public function test_a_branch_form_that_posts_the_list_back_unchanged_still_saves(): void
    {
        // The branch already holds `pickup` and the plan has no pickup flag:
        // renaming it must not be refused, and must not rewrite what is stored.
        $restaurant = $this->tenant(['dine_in']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant, ['pickup']);

        $this->save($owner, $branch, ['name_en' => 'Renamed', 'supported_order_types' => ['pickup']])->assertOk();

        $fresh = $branch->fresh();
        $this->assertSame('Renamed', $fresh->name_en);
        $this->assertSame(['pickup'], $fresh->supported_order_types, 'left exactly as the wizard wrote it');
    }

    public function test_an_empty_stored_list_means_all_and_stays_editable_without_it(): void
    {
        $restaurant = $this->tenant(['dine_in']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant, []);

        // Untouched: an unchanged [] is not "none".
        $this->save($owner, $branch, ['name_en' => 'Renamed', 'supported_order_types' => []])->assertOk();
        $this->assertSame([], $branch->fresh()->supported_order_types);
    }

    public function test_staff_need_the_capability_to_change_the_list(): void
    {
        $restaurant = $this->tenant(['dine_in', 'delivery']);
        $branch = $this->branch($restaurant, ['dine_in']);

        $editor = $this->staffWith($restaurant, ['branches.view', 'branches.update']);
        $this->save($editor, $branch, ['supported_order_types' => ['dine_in', 'delivery']])->assertForbidden();
        $this->assertSame(['dine_in'], $branch->fresh()->supported_order_types);

        // The same person can still edit the branch, posting the list unchanged.
        $this->save($editor, $branch, ['name_en' => 'Renamed', 'supported_order_types' => ['dine_in']])->assertOk();

        $manager = $this->staffWith($restaurant, ['branches.view', 'branches.update', 'pos.settings.order_types.manage']);
        $this->save($manager, $branch, ['supported_order_types' => ['dine_in', 'delivery']])->assertOk();
        $this->assertSame(['dine_in', 'delivery'], $branch->fresh()->supported_order_types);
    }

    public function test_the_capability_implies_pos_operate_and_keeps_its_exact_name(): void
    {
        $this->assertSame('pos.settings.order_types.manage', TenantCapability::POS_ORDER_TYPES_MANAGE->value);
        $this->assertSame('pos', TenantCapability::POS_ORDER_TYPES_MANAGE->resource());
        $this->assertSame(TenantCapability::POS_OPERATE, TenantCapability::POS_ORDER_TYPES_MANAGE->implies());
        $this->assertContains('pos.settings.order_types.manage', TenantCapability::expand(['pos.settings.order_types.manage']));
    }

    public function test_a_change_bumps_the_tills_config_version(): void
    {
        $restaurant = $this->tenant(['dine_in', 'delivery']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant, ['dine_in']);

        $before = (int) $restaurant->fresh()->pos_config_version;
        $this->save($owner, $branch, ['supported_order_types' => ['dine_in', 'delivery']])->assertOk();

        $this->assertGreaterThan($before, (int) $restaurant->fresh()->pos_config_version, 'connected tills are told to refresh');
    }

    public function test_the_branch_says_what_the_subscription_includes(): void
    {
        $restaurant = $this->tenant(['dine_in', 'pickup']);
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();
        $branch = $this->branch($restaurant);

        $this->actingAs($owner)->getJson('/api/dashboard/branches')
            ->assertOk()
            ->assertJsonPath('data.0.entitled_order_types', ['dine_in', 'takeaway']);
    }

    public function test_another_restaurants_branch_is_not_found(): void
    {
        $theirs = $this->branch($this->tenant(['dine_in']), ['dine_in']);
        $owner = User::factory()->restaurantAdmin($this->tenant(['dine_in'])->id)->create();

        $this->save($owner, $theirs, ['supported_order_types' => ['dine_in']])->assertNotFound();
    }

    public function test_normalise_is_stable_and_keeps_what_it_does_not_know(): void
    {
        $this->assertSame(['dine_in', 'takeaway', 'delivery'], OrderTypeEntitlements::normalise(['delivery', 'pickup', 'dine_in', 'takeaway']));
        $this->assertSame(['dine_in', 'curbside'], OrderTypeEntitlements::normalise(['curbside', 'dine_in']));
        $this->assertSame([], OrderTypeEntitlements::normalise([]));
    }
}

<?php

namespace Tests\Feature;

use App\Enums\TenantCapability;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Tests\TestCase;

/**
 * live-board-to-pos D9/D11: `live.view` no longer exists as a capability.
 *
 * Stored role rows are deliberately NOT rewritten (a deploy never changes tenant
 * data here, and rolling the code back restores the old behaviour). The removed
 * value is simply ignored when capabilities are read, so these tests pin that a
 * row still carrying it is inert, never an error, and never rewritten.
 */
class StaleLiveViewCapabilityTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->create();
        foreach (['system_ordering', 'bill_requests'] as $key) {
            $this->restaurant->features()->create(['feature_key' => $key, 'is_enabled' => true]);
        }
        $this->restaurant->load('features');
    }

    /** @param  list<string>  $caps */
    private function roleWith(array $caps): Role
    {
        $role = new Role(['name' => 'Stale '.uniqid()]);
        $role->forceFill([
            'restaurant_id' => $this->restaurant->id,
            'capabilities' => $caps,
            'is_system' => false,
        ])->save();

        return $role;
    }

    public function test_the_removed_value_is_ignored_and_the_other_capabilities_keep_working(): void
    {
        $role = $this->roleWith(['live.view', 'orders.view']);
        $actor = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->assertSame(['orders.view'], $role->fresh()->capabilityValues());
        $this->actingAs($actor)->getJson('/api/dashboard/orders')->assertOk();
        $this->actingAs($actor)->getJson('/api/dashboard/bill-requests')->assertForbidden();
    }

    public function test_a_role_holding_only_the_removed_value_has_no_capabilities(): void
    {
        $role = $this->roleWith(['live.view']);

        $this->assertSame([], $role->fresh()->capabilityValues());
    }

    public function test_requests_never_rewrite_the_stored_role_row(): void
    {
        $role = $this->roleWith(['live.view', 'orders.view']);
        $actor = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($actor)->getJson('/api/dashboard/orders')->assertOk();
        $this->actingAs($actor)->getJson('/api/auth/me')->assertOk();

        $this->assertSame(
            ['live.view', 'orders.view'],
            json_decode(DB::table('roles')->where('id', $role->id)->value('capabilities'), true),
        );
    }

    /** The retired case exists only for the shipped migration; nothing user-facing sees it. */
    public function test_the_retired_case_is_excluded_everywhere_it_could_leak(): void
    {
        $this->assertNotContains('live.view', TenantCapability::values());
        $this->assertNotContains(TenantCapability::LIVE_VIEW, TenantCapability::active());
        $this->assertNull(TenantCapability::tryFromActive('live.view'));
        $this->assertSame([], TenantCapability::expand(['live.view']));
        $this->assertFalse(Gate::has('live.view'));
    }
}

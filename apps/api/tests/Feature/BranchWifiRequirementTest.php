<?php

namespace Tests\Feature;

use App\Enums\RestaurantStatus;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * The opt-in hard gate: while a branch requires its own customer Wi-Fi, a table
 * scan that does not arrive from one of its known addresses is refused.
 *
 * This deliberately contradicts what the egress signal can actually support —
 * a miss is not evidence of absence — so the tests pin down both halves: that
 * it really does refuse when switched on, and that it changes nothing at all
 * for the branches (the default) that leave it off.
 */
class BranchWifiRequirementTest extends TestCase
{
    use RefreshDatabase;

    private Restaurant $restaurant;

    private Branch $branch;

    private DiningTable $table;

    /** The branch's own line, RFC 5737 documentation range. */
    private const SHOP_IP = '203.0.113.10';

    /** A diner on mobile data — a different carrier address entirely. */
    private const MOBILE_IP = '198.51.100.42';

    protected function setUp(): void
    {
        parent::setUp();
        $this->restaurant = Restaurant::factory()->withOrdering()->create([
            'status' => RestaurantStatus::ACTIVE, 'slug' => 'cafe',
        ]);
        $this->branch = new Branch(['name_en' => 'Main']);
        $this->branch->restaurant_id = $this->restaurant->id;
        $this->branch->save();
        $area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Indoor']);
        $area->restaurant_id = $this->restaurant->id;
        $area->save();
        $this->table = new DiningTable([
            'dining_area_id' => $area->id, 'label' => '12',
            'public_token' => DiningTable::generateToken(), 'is_active' => true,
            'qr_generated_at' => now(),
        ]);
        $this->table->restaurant_id = $this->restaurant->id;
        $this->table->branch_id = $this->branch->id;
        $this->table->save();
    }

    /** Switch the requirement on, with the shop's address on file. */
    private function requireWifi(): void
    {
        $this->branch->forceFill([
            'egress_ips_manual' => [self::SHOP_IP],
            'require_branch_wifi' => true,
        ])->save();
    }

    private function scan(string $ip)
    {
        return $this->withServerVariables(['REMOTE_ADDR' => $ip])
            ->postJson("/api/public/tables/{$this->table->public_token}/sessions", []);
    }

    private function order(string $ip, string $sessionToken)
    {
        return $this->withServerVariables(['REMOTE_ADDR' => $ip])
            ->postJson('/api/public/restaurants/cafe/orders', [
                'items' => [['name' => 'Latte', 'qty' => 1, 'line_total' => 50]],
                'total' => 50,
                'session_token' => $sessionToken,
            ]);
    }

    // ── The gate at scan time ──────────────────────────────────────────────

    public function test_scan_from_the_branch_wifi_is_admitted(): void
    {
        $this->requireWifi();

        $this->scan(self::SHOP_IP)->assertCreated();
    }

    public function test_scan_from_mobile_data_is_refused_while_the_requirement_is_on(): void
    {
        $this->requireWifi();

        $this->scan(self::MOBILE_IP)
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.table_requires_branch_wifi'));

        $this->assertDatabaseCount('menu_sessions', 0);
    }

    public function test_the_default_branch_admits_a_scan_from_anywhere(): void
    {
        // Nothing switched on: the signal is recorded, never enforced. This is
        // the behaviour every existing branch keeps.
        $this->scan(self::MOBILE_IP)->assertCreated();
    }

    public function test_a_recorded_address_alone_does_not_gate_a_scan(): void
    {
        $this->branch->forceFill(['egress_ips_manual' => [self::SHOP_IP]])->save();

        $this->scan(self::MOBILE_IP)->assertCreated();
    }

    public function test_the_requirement_fails_closed_when_no_address_is_on_file(): void
    {
        // Reachable only by clearing the addresses after switching the gate on
        // (the dashboard refuses to enable it empty — see below). It must not
        // silently degrade to "let everyone in".
        $this->branch->forceFill([
            'egress_ips_manual' => null, 'egress_ips' => null, 'require_branch_wifi' => true,
        ])->save();

        $this->scan(self::SHOP_IP)->assertStatus(422);
    }

    public function test_a_learned_address_satisfies_the_requirement_too(): void
    {
        $this->branch->forceFill([
            'egress_ips' => [self::SHOP_IP], 'require_branch_wifi' => true,
        ])->save();

        $this->scan(self::SHOP_IP)->assertCreated();
    }

    // ── The gate at order time ─────────────────────────────────────────────

    public function test_order_is_refused_when_the_diner_leaves_the_wifi_after_scanning(): void
    {
        $this->requireWifi();
        $token = $this->scan(self::SHOP_IP)->assertCreated()->json('data.session_token');

        // Joined the Wi-Fi to open the session, then switched back to mobile
        // data to order — the bypass the scan-time check alone would allow.
        $this->order(self::MOBILE_IP, $token)
            ->assertStatus(422)
            ->assertJsonPath('message', __('xorder.messages.table_requires_branch_wifi'));

        $this->assertDatabaseCount('orders', 0);
    }

    public function test_order_from_the_branch_wifi_goes_through_and_stays_bound_to_the_table(): void
    {
        $this->requireWifi();
        $token = $this->scan(self::SHOP_IP)->assertCreated()->json('data.session_token');

        $this->order(self::SHOP_IP, $token)->assertCreated();

        $this->assertDatabaseHas('orders', [
            'table_id' => $this->table->id,
            'branch_id' => $this->branch->id,
            'order_type' => 'dine_in',
        ]);
    }

    public function test_order_on_a_default_branch_is_unaffected_by_the_diner_network(): void
    {
        $token = $this->scan(self::MOBILE_IP)->assertCreated()->json('data.session_token');

        $this->order(self::MOBILE_IP, $token)->assertCreated();
    }

    // ── The dashboard switch ───────────────────────────────────────────────

    private function admin(): User
    {
        return User::factory()->restaurantAdmin($this->restaurant->id)->create();
    }

    public function test_enabling_the_requirement_without_an_address_is_rejected(): void
    {
        $this->actingAs($this->admin())
            ->putJson("/api/dashboard/branches/{$this->branch->id}", [
                'name_en' => 'Main', 'require_branch_wifi' => true,
            ])
            ->assertStatus(422)
            ->assertJsonValidationErrors('require_branch_wifi');

        $this->assertFalse((bool) $this->branch->fresh()->require_branch_wifi);
    }

    public function test_enabling_the_requirement_with_an_address_on_file_is_allowed(): void
    {
        $this->branch->forceFill(['egress_ips_manual' => [self::SHOP_IP]])->save();

        $this->actingAs($this->admin())
            ->putJson("/api/dashboard/branches/{$this->branch->id}", [
                'name_en' => 'Main', 'require_branch_wifi' => true,
            ])
            ->assertOk();

        $this->assertTrue((bool) $this->branch->fresh()->require_branch_wifi);
    }

    public function test_another_tenant_cannot_switch_the_requirement_on(): void
    {
        $this->branch->forceFill(['egress_ips_manual' => [self::SHOP_IP]])->save();
        $other = Restaurant::factory()->create(['status' => RestaurantStatus::ACTIVE]);
        $intruder = User::factory()->restaurantAdmin($other->id)->create();

        $this->actingAs($intruder)
            ->putJson("/api/dashboard/branches/{$this->branch->id}", [
                'name_en' => 'Main', 'require_branch_wifi' => true,
            ])
            ->assertNotFound();

        $this->assertFalse((bool) $this->branch->fresh()->require_branch_wifi);
    }
}

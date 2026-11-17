<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * dashboard-shift-details: the back office reads one shift (the till report's
 * figures) and force-closes a shift whose till was revoked before closing it.
 * Owner decisions 2026-11-09: revoked tills only; counted cash and a reason
 * both required; anyone holding pos.shift_close.
 */
class DashboardShiftTest extends PosTestCase
{
    private PosTerminal $terminal;

    private PosShift $shift;

    protected function setUp(): void
    {
        parent::setUp();

        $claim = $this->claimTerminal();
        $this->terminal = $claim['terminal'];
        $headers = $this->deviceHeaders($claim['token']);

        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();
        $card = new TenderType(['name' => 'Card', 'kind' => 'card']);
        $card->restaurant_id = $this->restaurant->id;
        $card->save();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $item = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00, 'discounted_price' => null,
        ]);

        $shiftClientId = (string) Str::uuid();
        $this->postJson('/api/pos/shifts', [
            'client_transaction_id' => $shiftClientId,
            'branch_id' => $this->branch->id,
            'opened_at' => '2026-09-02T08:00:00+02:00',
            'opening_float_minor' => 10000,
        ], $headers)->assertCreated();

        // 200.00 sold, 150 cash / 50 card; cash in 3000, out 1000.
        $this->postJson('/api/pos/orders', [
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-09-02T10:00:00+02:00',
            'shift_client_id' => $shiftClientId,
            'lines' => [['menu_item_id' => $item->id, 'quantity' => 2, 'name_snapshot' => 'Burger']],
            'payments' => [
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $cash->id, 'amount_minor' => 15000],
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $card->id, 'amount_minor' => 5000],
            ],
        ], $headers)->assertCreated();
        foreach ([['in', 3000], ['out', 1000]] as [$direction, $amount]) {
            $this->postJson('/api/pos/cash-movements', [
                'client_transaction_id' => (string) Str::uuid(), 'shift_client_id' => $shiftClientId,
                'direction' => $direction, 'amount_minor' => $amount, 'reason' => 'test',
                'occurred_at' => '2026-09-02T11:00:00+02:00',
            ], $headers)->assertCreated();
        }

        $this->shift = PosShift::withoutGlobalScopes()->where('client_transaction_id', $shiftClientId)->firstOrFail();
        $this->app['auth']->forgetGuards();
    }

    private function revokeTill(): void
    {
        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$this->terminal->id}/revoke")
            ->assertOk();
    }

    private function forceClose(User $as, array $payload = ['counted_cash_minor' => 26500, 'reason' => 'Till revoked mid-shift'])
    {
        return $this->actingAs($as)->postJson("/api/dashboard/pos/shifts/{$this->shift->id}/force-close", $payload);
    }

    /** A staff account whose role holds exactly these capabilities. */
    private function staffWith(array $capabilities): User
    {
        $role = new Role(['name' => 'Role '.Str::random(6)]);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => $capabilities])->save();

        return User::factory()->staff($this->restaurant->id, $role->id)->create();
    }

    // ------------------------------------------------------------- show

    public function test_the_page_reads_the_same_figures_as_the_tills_report(): void
    {
        $data = $this->actingAs($this->owner)
            ->getJson("/api/dashboard/pos/shifts/{$this->shift->id}")
            ->assertOk()->json('data');

        $this->assertSame('open', $data['status']);
        $this->assertNull($data['closed_via']);
        $this->assertSame('Till 1', $data['terminal']['name']);
        $this->assertFalse($data['terminal']['revoked']);
        $this->assertFalse($data['can_force_close']);
        $this->assertSame(10000, $data['opening_float_minor']);
        // A3: 10000 + 15000 cash + 3000 in − 1000 out.
        $this->assertSame(27000, $data['expected_cash_minor']);
        $this->assertSame(1, $data['summary']['orders_count']);
        $this->assertSame(20000, $data['summary']['sales_minor']);
        $this->assertSame(3000, $data['summary']['cash_in_minor']);
        $this->assertSame(1000, $data['summary']['cash_out_minor']);
        $this->assertCount(1, $data['orders']);
        $this->assertCount(2, $data['cash_movements']);
    }

    public function test_another_tenants_shift_is_invisible(): void
    {
        $other = Restaurant::factory()->create();
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $stranger = User::factory()->restaurantAdmin($other->id)->create();

        $this->actingAs($stranger)->getJson("/api/dashboard/pos/shifts/{$this->shift->id}")->assertNotFound();

        $this->revokeTill();
        $this->forceClose($stranger)->assertNotFound();
        $this->assertTrue($this->shift->fresh()->isOpen());
    }

    public function test_reading_needs_analytics_view(): void
    {
        $this->actingAs($this->staffWith(['pos.operate']))
            ->getJson("/api/dashboard/pos/shifts/{$this->shift->id}")->assertForbidden();

        $this->actingAs($this->staffWith(['analytics.view']))
            ->getJson("/api/dashboard/pos/shifts/{$this->shift->id}")->assertOk();
    }

    // ------------------------------------------------------ force close

    public function test_a_revoked_tills_shift_is_force_closed_with_the_servers_variance(): void
    {
        $this->revokeTill();

        $before = $this->actingAs($this->owner)->getJson("/api/dashboard/pos/shifts/{$this->shift->id}")->json('data');
        $this->assertTrue($before['can_force_close']);

        $data = $this->forceClose($this->owner)->assertOk()->json('data');

        $this->assertSame('closed', $data['status']);
        $this->assertSame('dashboard', $data['closed_via']);
        $this->assertSame(26500, $data['counted_cash_minor']);
        $this->assertSame(27000, $data['expected_cash_minor']);
        $this->assertSame(-500, $data['variance_minor']);
        $this->assertSame('Till revoked mid-shift', $data['variance_reason']);
        $this->assertSame($this->owner->name, $data['closed_by']);
        $this->assertFalse($data['can_force_close']);

        $shift = $this->shift->fresh();
        $this->assertSame($this->owner->id, $shift->closed_by_id);
        $this->assertNotNull($shift->closed_at);
        $this->assertNull($shift->close_payload_hash, 'no till payload behind a dashboard close');
    }

    public function test_a_live_tills_shift_is_refused(): void
    {
        $this->forceClose($this->owner)
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_NOT_REVOKED');

        $this->assertTrue($this->shift->fresh()->isOpen());
    }

    public function test_a_closed_shift_is_not_closed_twice(): void
    {
        $this->revokeTill();
        $this->forceClose($this->owner)->assertOk();

        $this->forceClose($this->owner, ['counted_cash_minor' => 1, 'reason' => 'again'])
            ->assertStatus(422)->assertJsonPath('code', 'SHIFT_NOT_OPEN');

        $this->assertSame(26500, $this->shift->fresh()->counted_cash_minor);
    }

    public function test_counted_cash_and_a_reason_are_both_required(): void
    {
        $this->revokeTill();

        $this->forceClose($this->owner, ['reason' => 'Till revoked'])
            ->assertStatus(422)->assertJsonValidationErrors('counted_cash_minor');
        $this->forceClose($this->owner, ['counted_cash_minor' => 27000])
            ->assertStatus(422)->assertJsonValidationErrors('reason');
        $this->forceClose($this->owner, ['counted_cash_minor' => -1, 'reason' => 'Till revoked'])
            ->assertStatus(422)->assertJsonValidationErrors('counted_cash_minor');

        $this->assertTrue($this->shift->fresh()->isOpen());
    }

    public function test_force_closing_needs_pos_shift_close(): void
    {
        $this->revokeTill();

        $this->forceClose($this->staffWith(['analytics.view']))->assertForbidden();
        $this->assertTrue($this->shift->fresh()->isOpen());

        $this->forceClose($this->staffWith(['pos.shift_close']))->assertOk();
    }
}

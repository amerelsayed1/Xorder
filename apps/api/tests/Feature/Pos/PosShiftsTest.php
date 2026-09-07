<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\PosShift;
use App\Models\TenderType;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * POS-BE-009: the shift lifecycle, the A3 expected-cash formula, and the
 * branch-scoped report. Client times stored as sent (instant-preserved),
 * received_at beside them.
 */
class PosShiftsTest extends PosTestCase
{
    private ?string $deviceToken = null;

    private function token(): string
    {
        return $this->deviceToken ??= $this->claimTerminal()['token'];
    }

    /** @return array<string,mixed> */
    private function openPayload(array $overrides = []): array
    {
        return array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'opened_at' => '2026-09-02T08:00:00+02:00',
            'opening_float_minor' => 10000,
        ], $overrides);
    }

    // ------------------------------------------------------- lifecycle

    public function test_open_current_close_lifecycle(): void
    {
        $token = $this->token();

        $opened = $this->postJson('/api/pos/shifts', $this->openPayload(), $this->deviceHeaders($token))
            ->assertCreated()->json('data');

        $this->assertSame('open', $opened['status']);
        $this->assertSame(10000, $opened['opening_float_minor']);
        // The client's opening instant is preserved exactly.
        $this->assertTrue(Carbon::parse('2026-09-02T08:00:00+02:00')->equalTo($opened['opened_at']));

        // received_at is the server's own observation, stored beside it.
        $shift = PosShift::withoutGlobalScopes()->find($opened['id']);
        $this->assertNotNull($shift->received_at);

        $current = $this->getJson('/api/pos/shifts/current', $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame($opened['id'], $current['id']);

        $closed = $this->postJson("/api/pos/shifts/{$opened['id']}/close", [
            'client_transaction_id' => (string) Str::uuid(),
            'closed_at' => '2026-09-02T23:30:00+02:00',
            'counted_cash_minor' => 10000, // nothing sold: counted == float
        ], $this->deviceHeaders($token))->assertOk()->json('data');

        $this->assertSame('closed', $closed['status']);
        $this->assertSame(10000, $closed['expected_cash_minor']);
        $this->assertSame(0, $closed['variance_minor']);

        $this->assertNull($this->getJson('/api/pos/shifts/current', $this->deviceHeaders($token))->json('data'));
    }

    public function test_one_open_shift_per_terminal_and_replay_semantics(): void
    {
        $token = $this->token();
        $payload = $this->openPayload();

        $first = $this->postJson('/api/pos/shifts', $payload, $this->deviceHeaders($token))
            ->assertCreated()->json('data');

        // Same key → same shift, 200 — the till retried a timeout.
        $replay = $this->postJson('/api/pos/shifts', $payload, $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame($first['id'], $replay['id']);

        // A DIFFERENT key while one is open → the terminal already has one.
        $this->postJson('/api/pos/shifts', $this->openPayload(), $this->deviceHeaders($token))
            ->assertStatus(422)->assertJsonPath('code', 'SHIFT_ALREADY_OPEN');
    }

    // ------------------------------------------------------- expected cash

    public function test_expected_cash_follows_the_a3_formula(): void
    {
        $token = $this->token();

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
        $this->postJson('/api/pos/shifts', $this->openPayload(['client_transaction_id' => $shiftClientId]), $this->deviceHeaders($token))
            ->assertCreated();

        // A 200.00 sale split 150 cash / 50 card, tied to the shift.
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
        ], $this->deviceHeaders($token))->assertCreated();

        // Cash in 3000, cash out 1000.
        $this->postJson('/api/pos/cash-movements', [
            'client_transaction_id' => (string) Str::uuid(), 'shift_client_id' => $shiftClientId,
            'direction' => 'in', 'amount_minor' => 3000, 'reason' => 'change float',
            'occurred_at' => '2026-09-02T11:00:00+02:00',
        ], $this->deviceHeaders($token))->assertCreated();
        $this->postJson('/api/pos/cash-movements', [
            'client_transaction_id' => (string) Str::uuid(), 'shift_client_id' => $shiftClientId,
            'direction' => 'out', 'amount_minor' => 1000, 'reason' => 'supplier',
            'reference' => 'invoice 4471',
            'occurred_at' => '2026-09-02T12:00:00+02:00',
        ], $this->deviceHeaders($token))->assertCreated();

        // A3: 10000 float + 15000 cash sales + 3000 in − 1000 out = 27000.
        // The card leg never touches the drawer.
        $report = $this->getJson("/api/pos/shifts/{$shiftClientId}/report", $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame(27000, $report['expected_cash_minor']);
        $this->assertSame(1, $report['orders_count']);
        $this->assertSame(3000, $report['cash_in_minor']);
        $this->assertSame(1000, $report['cash_out_minor']);

        $byKind = collect($report['sales_by_tender'])->keyBy('kind');
        $this->assertSame(15000, $byKind['cash']['amount_minor']);
        $this->assertSame(5000, $byKind['card']['amount_minor']);

        // Close over by 500 without a reason → refused; with one → recorded.
        $close = [
            'client_transaction_id' => (string) Str::uuid(),
            'closed_at' => '2026-09-02T23:00:00+02:00',
            'counted_cash_minor' => 27500,
        ];
        $this->postJson("/api/pos/shifts/{$shiftClientId}/close", $close, $this->deviceHeaders($token))
            ->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');

        $closed = $this->postJson("/api/pos/shifts/{$shiftClientId}/close",
            $close + ['variance_reason' => 'tips in drawer'], $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame(500, $closed['variance_minor']);
        $this->assertSame(27000, $closed['expected_cash_minor']);
    }

    // ------------------------------------------------------- guards

    public function test_cash_movements_require_an_open_shift(): void
    {
        $this->postJson('/api/pos/cash-movements', [
            'client_transaction_id' => (string) Str::uuid(),
            'shift_client_id' => (string) Str::uuid(), // never opened
            'direction' => 'in', 'amount_minor' => 1000, 'reason' => 'float',
            'occurred_at' => '2026-09-02T11:00:00+02:00',
        ], $this->deviceHeaders($this->token()))
            ->assertStatus(422)->assertJsonPath('code', 'SHIFT_NOT_OPEN');
    }

    public function test_close_replays_idempotently_and_a_second_close_is_refused(): void
    {
        $token = $this->token();
        $shiftClientId = (string) Str::uuid();

        $this->postJson('/api/pos/shifts', $this->openPayload(['client_transaction_id' => $shiftClientId]), $this->deviceHeaders($token));

        $close = [
            'client_transaction_id' => (string) Str::uuid(),
            'closed_at' => '2026-09-02T23:00:00+02:00',
            'counted_cash_minor' => 10000,
        ];

        $first = $this->postJson("/api/pos/shifts/{$shiftClientId}/close", $close, $this->deviceHeaders($token))
            ->assertOk()->json('data');

        // Replaying the SAME close returns the same closed shift.
        $replay = $this->postJson("/api/pos/shifts/{$shiftClientId}/close", $close, $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame($first['id'], $replay['id']);

        // A DIFFERENT close against a closed shift is refused.
        $this->postJson("/api/pos/shifts/{$shiftClientId}/close", [
            'client_transaction_id' => (string) Str::uuid(),
            'closed_at' => '2026-09-02T23:59:00+02:00',
            'counted_cash_minor' => 99999,
        ], $this->deviceHeaders($token))
            ->assertStatus(422)->assertJsonPath('code', 'SHIFT_NOT_OPEN');
    }

    public function test_the_report_is_scoped_to_the_requesting_terminals_branch(): void
    {
        $token = $this->token();

        // A second branch with its own terminal and open shift.
        $second = new Branch(['name_en' => 'Zamalek', 'code' => 'ZMLK']);
        $second->restaurant_id = $this->restaurant->id;
        $second->save();

        $provision = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till Z', 'branch_id' => $second->id])
            ->json('data');
        $code = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")
            ->json('pairing_code');
        $zToken = $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug, 'pairing_code' => $code,
            'fingerprint' => 'sha256:z',
        ])->json('device_token');

        $zShift = $this->postJson('/api/pos/shifts', [
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $second->id,
            'opened_at' => '2026-09-02T08:00:00+02:00',
            'opening_float_minor' => 5000,
        ], $this->deviceHeaders($zToken))->assertCreated()->json('data');

        // The MAADI till cannot read the Zamalek drawer — BE-A02's ask: a
        // cashier pressing the report key must not see another branch's cash.
        $this->getJson("/api/pos/shifts/{$zShift['id']}/report", $this->deviceHeaders($token))
            ->assertStatus(422);

        // Its own terminal reads it fine.
        $this->getJson("/api/pos/shifts/{$zShift['id']}/report", $this->deviceHeaders($zToken))
            ->assertOk();
    }
}

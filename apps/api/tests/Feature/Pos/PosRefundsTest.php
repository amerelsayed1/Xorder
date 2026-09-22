<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\PosRefund;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Str;

/**
 * POS-BE-010 — refunds as reversing records.
 *
 * The load-bearing assertions are the ones the till cannot negotiate: the
 * original order is never mutated, a line can never give back more than it
 * sold, a refund can be addressed by the till's OWN line key (the reason no
 * cloud till has ever uploaded one), and a replay returns the identical body
 * with the same credit note number.
 */
class PosRefundsTest extends PosTestCase
{
    private MenuItem $burger;

    private TenderType $cash;

    private ?string $deviceToken = null;

    protected function setUp(): void
    {
        parent::setUp();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $this->burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.00,
            'discounted_price' => null,
        ]);

        $cash = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $cash->restaurant_id = $this->restaurant->id;
        $cash->save();
        $this->cash = $cash;
    }

    private function token(): string
    {
        return $this->deviceToken ??= $this->claimTerminal()['token'];
    }

    /** An order of 2 × 100.00 EGP, paid in cash, with the till's own line key. */
    private function sell(array $overrides = []): array
    {
        return $this->postJson('/api/pos/orders', array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-09-22T08:00:00+02:00',
            'lines' => [[
                'client_line_id' => 'L1',
                'menu_item_id' => $this->burger->id,
                'quantity' => 2,
                'name_snapshot' => 'Classic Burger',
            ]],
            'payments' => [[
                'client_transaction_id' => (string) Str::uuid(),
                'tender_type_id' => $this->cash->id,
                'amount_minor' => 20000,
            ]],
        ], $overrides), $this->deviceHeaders($this->token()))->assertCreated()->json('data');
    }

    /** @return array<string,mixed> */
    private function refundPayload(array $order, array $overrides = []): array
    {
        return array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            // Addressed by the ORDER'S client key, not its server id: an
            // offline till refunding an order still in its outbox knows only
            // that much.
            'order_id' => $order['client_transaction_id'],
            'kind' => 'refund',
            'reason' => 'cold food',
            'occurred_at' => '2026-09-22T09:00:00+02:00',
            'lines' => [['client_line_id' => 'L1', 'quantity' => 1, 'amount_minor' => 10000]],
            'tenders' => [['tender_type_id' => $this->cash->id, 'amount_minor' => 10000]],
        ], $overrides);
    }

    // ------------------------------------------------- the reversing record

    public function test_a_refund_is_a_new_record_and_never_touches_the_original(): void
    {
        $order = $this->sell();
        $before = Order::withoutGlobalScopes()->find($order['id']);

        $body = $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($this->token()))
            ->assertCreated()->json('data');

        $after = Order::withoutGlobalScopes()->find($order['id']);

        // The order's own lifecycle state is untouched (A4) — refund state is
        // carried by the DERIVED settlement status, not by OrderStatus.
        $this->assertSame($before->status, $after->status);
        $this->assertSame('NEW', $after->status->value);
        $this->assertSame((int) $before->total_minor, (int) $after->total_minor);
        $this->assertSame('PARTIALLY_REFUNDED', $body['order']['settlement_status']);
        $this->assertSame(10000, $body['order']['refunded_minor']);

        // The credit note is its own series, so refunds never consume invoice
        // numbers: the sale kept MAADI-2026-000001.
        $this->assertSame('CN-MAADI-2026-000001', $body['credit_note_number']);
        $this->assertSame('MAADI-2026-000001', $body['order']['invoice_number']);
        $this->assertSame('MAADI-2026-000001', $body['order']['invoice_number']);
        $this->assertSame(10000, $body['totals']['total_minor']);
        $this->assertSame('L1', $body['lines'][0]['client_line_id']);
        $this->assertSame(1, $body['lines'][0]['quantity']);
    }

    public function test_refunding_everything_taken_reads_refunded(): void
    {
        $order = $this->sell();

        $body = $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'lines' => [['client_line_id' => 'L1', 'quantity' => 2, 'amount_minor' => 20000]],
            'tenders' => [['tender_type_id' => $this->cash->id, 'amount_minor' => 20000]],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        $this->assertSame('REFUNDED', $body['order']['settlement_status']);

        // And the order read-back agrees — one derivation, two callers.
        $reread = $this->getJson('/api/pos/orders/by-client-id/'.$order['client_transaction_id'], $this->deviceHeaders($this->token()))
            ->assertOk()->json('data');
        $this->assertSame('REFUNDED', $reread['settlement_status']);
        $this->assertSame(20000, $reread['refunded_minor']);
        $this->assertSame(2, $reread['lines'][0]['refunded_quantity']);
    }

    // ------------------------------------------------- the exceeds-sold rule

    public function test_a_line_can_never_give_back_more_than_it_sold(): void
    {
        $order = $this->sell();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'lines' => [['client_line_id' => 'L1', 'quantity' => 3, 'amount_minor' => 30000]],
            'tenders' => [['tender_type_id' => $this->cash->id, 'amount_minor' => 30000]],
        ]), $this->deviceHeaders($this->token()))
            ->assertStatus(422)
            ->assertJsonPath('code', 'REFUND_EXCEEDS_SOLD')
            ->assertJsonPath('details.sold_quantity', 2)
            ->assertJsonPath('details.requested_quantity', 3);

        $this->assertSame(0, PosRefund::withoutGlobalScopes()->count());
    }

    public function test_the_check_is_cumulative_across_refunds(): void
    {
        $order = $this->sell();
        $token = $this->token();

        // Two of two, one at a time: the second is fine, the third is not.
        $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($token))->assertCreated();
        $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($token))->assertCreated();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($token))
            ->assertStatus(422)
            ->assertJsonPath('code', 'REFUND_EXCEEDS_SOLD')
            ->assertJsonPath('details.already_refunded_quantity', 2);

        $this->assertSame(2, PosRefund::withoutGlobalScopes()->count());
        $this->assertSame(20000, (int) Order::withoutGlobalScopes()->find($order['id'])->refunded_minor);
    }

    public function test_money_back_can_never_exceed_what_the_sale_was_worth(): void
    {
        $order = $this->sell();

        // Quantity is within the sold count; the AMOUNT is not.
        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'lines' => [['client_line_id' => 'L1', 'quantity' => 1, 'amount_minor' => 50000]],
            'tenders' => [['tender_type_id' => $this->cash->id, 'amount_minor' => 50000]],
        ]), $this->deviceHeaders($this->token()))
            ->assertStatus(422)
            ->assertJsonPath('code', 'REFUND_EXCEEDS_SOLD')
            ->assertJsonPath('details.order_total_minor', 20000);
    }

    public function test_tenders_must_equal_the_lines(): void
    {
        $order = $this->sell();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'tenders' => [['tender_type_id' => $this->cash->id, 'amount_minor' => 9000]],
        ]), $this->deviceHeaders($this->token()))
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_FAILED');
    }

    // ------------------------------------------------- idempotency

    public function test_a_replay_returns_the_identical_body_and_never_409(): void
    {
        $order = $this->sell();
        $token = $this->token();
        $payload = $this->refundPayload($order);

        $first = $this->postJson('/api/pos/refunds', $payload, $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $replay = $this->postJson('/api/pos/refunds', $payload, $this->deviceHeaders($token))
            ->assertOk()->json('data'); // 2xx, NEVER 409

        $this->assertSame($first, $replay); // id + credit note number included
        $this->assertSame(1, PosRefund::withoutGlobalScopes()->count());

        // The replay consumed no credit note number and moved no counter.
        $this->assertSame(10000, (int) Order::withoutGlobalScopes()->find($order['id'])->refunded_minor);

        $next = $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $this->assertSame('CN-MAADI-2026-000002', $next['credit_note_number']);
    }

    public function test_the_same_key_with_different_money_is_a_client_bug(): void
    {
        $order = $this->sell();
        $token = $this->token();
        $payload = $this->refundPayload($order);

        $this->postJson('/api/pos/refunds', $payload, $this->deviceHeaders($token))->assertCreated();

        $payload['lines'][0]['amount_minor'] = 5000;
        $payload['tenders'][0]['amount_minor'] = 5000;

        $this->postJson('/api/pos/refunds', $payload, $this->deviceHeaders($token))
            ->assertStatus(422)->assertJsonPath('code', 'IDEMPOTENCY_PAYLOAD_MISMATCH');
    }

    public function test_by_client_id_recovers_the_full_body(): void
    {
        $order = $this->sell();
        $token = $this->token();
        $payload = $this->refundPayload($order);

        $created = $this->postJson('/api/pos/refunds', $payload, $this->deviceHeaders($token))->json('data');

        $recovered = $this->getJson('/api/pos/refunds/by-client-id/'.$payload['client_transaction_id'], $this->deviceHeaders($token))
            ->assertOk()->json('data');

        $this->assertSame($created, $recovered);

        $this->getJson('/api/pos/refunds/by-client-id/'.Str::uuid(), $this->deviceHeaders($token))
            ->assertNotFound();
    }

    // ------------------------------------------------- addressing + isolation

    public function test_a_line_may_also_be_named_by_its_server_id(): void
    {
        $order = $this->sell();

        $body = $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'order_id' => (string) $order['id'],
            'lines' => [['order_item_id' => $order['lines'][0]['id'], 'quantity' => 1, 'amount_minor' => 10000]],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        $this->assertSame($order['lines'][0]['id'], $body['lines'][0]['order_item_id']);
    }

    public function test_a_line_named_two_ways_or_no_way_is_refused(): void
    {
        $order = $this->sell();
        $token = $this->token();

        foreach ([
            ['order_item_id' => $order['lines'][0]['id'], 'client_line_id' => 'L1', 'quantity' => 1, 'amount_minor' => 10000],
            ['quantity' => 1, 'amount_minor' => 10000],
        ] as $line) {
            $this->postJson('/api/pos/refunds', $this->refundPayload($order, ['lines' => [$line]]), $this->deviceHeaders($token))
                ->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');
        }
    }

    public function test_a_line_of_another_order_is_not_on_that_order(): void
    {
        $token = $this->token();
        $first = $this->sell();
        $second = $this->sell(['lines' => [[
            'client_line_id' => 'L9', 'menu_item_id' => $this->burger->id,
            'quantity' => 1, 'name_snapshot' => 'Classic Burger',
        ]], 'payments' => []]);

        $this->postJson('/api/pos/refunds', $this->refundPayload($first, [
            'lines' => [['order_item_id' => $second['lines'][0]['id'], 'quantity' => 1, 'amount_minor' => 10000]],
        ]), $this->deviceHeaders($token))->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');
    }

    public function test_another_tenants_order_is_invisible(): void
    {
        $order = $this->sell();
        $token = $this->token();

        // A second POS tenant with its own terminal and its own sale.
        $other = Restaurant::factory()->create(['currency' => 'EGP']);
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        $foreignRefund = $this->refundPayload($order, ['order_id' => $order['client_transaction_id']]);

        // Same tenant, same terminal: allowed. Then prove the reverse — a
        // refund quoting this order under ANOTHER tenant's device token cannot
        // see it at all.
        $this->postJson('/api/pos/refunds', $foreignRefund, $this->deviceHeaders($token))->assertCreated();

        $foreign = $this->claimForeignTerminal($other);

        $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($foreign))
            ->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');

        $this->assertSame(1, PosRefund::withoutGlobalScopes()->count());
    }

    public function test_an_unknown_tender_is_refused(): void
    {
        $order = $this->sell();
        $foreignTender = new TenderType(['name' => 'Cash', 'kind' => 'cash']);
        $foreignTender->restaurant_id = Restaurant::factory()->create()->id;
        $foreignTender->save();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'tenders' => [['tender_type_id' => $foreignTender->id, 'amount_minor' => 10000]],
        ]), $this->deviceHeaders($this->token()))
            ->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');
    }

    // ------------------------------------------------- capability + gates

    public function test_a_named_cashier_needs_pos_refund(): void
    {
        $order = $this->sell();

        $role = new Role(['name' => 'Cashier']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate']])->save(); // no pos.refund
        $cashier = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'acting_user_id' => $cashier->id,
        ]), $this->deviceHeaders($this->token()))
            ->assertForbidden()
            ->assertJsonPath('code', 'POS_CAPABILITY_MISSING')
            ->assertJsonPath('details.capability', 'pos.refund');
    }

    public function test_a_void_asks_for_pos_void_instead(): void
    {
        $order = $this->sell();

        $role = new Role(['name' => 'Refunder']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate', 'pos.refund']])->save(); // no pos.void
        $cashier = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'kind' => 'void',
            'acting_user_id' => $cashier->id,
        ]), $this->deviceHeaders($this->token()))
            ->assertForbidden()
            ->assertJsonPath('details.capability', 'pos.void');
    }

    public function test_the_device_credential_is_the_only_way_in(): void
    {
        $order = $this->sell();

        $this->postJson('/api/pos/refunds', $this->refundPayload($order))
            ->assertStatus(401)->assertJsonPath('code', 'DEVICE_TOKEN_INVALID');

        // A dashboard JWT is not a till credential, whatever it holds.
        $this->actingAs($this->owner)
            ->postJson('/api/pos/refunds', $this->refundPayload($order))
            ->assertStatus(401);
    }

    public function test_a_pos_less_tenant_is_refused_at_the_feature_gate(): void
    {
        $order = $this->sell();
        $this->restaurant->features()->where('feature_key', 'pos')->update(['is_enabled' => false]);

        $this->postJson('/api/pos/refunds', $this->refundPayload($order), $this->deviceHeaders($this->token()))
            ->assertForbidden()->assertJsonPath('code', 'POS_FEATURE_DISABLED');
    }

    // ------------------------------------------------- the drawer

    public function test_cash_handed_back_leaves_the_drawer_short(): void
    {
        $token = $this->token();

        $shiftKey = (string) Str::uuid();
        $this->postJson('/api/pos/shifts', [
            'client_transaction_id' => $shiftKey,
            'branch_id' => $this->branch->id,
            'opened_at' => '2026-09-22T08:00:00+02:00',
            'opening_float_minor' => 50000,
        ], $this->deviceHeaders($token))->assertCreated();

        $order = $this->sell(['shift_client_id' => $shiftKey]);

        $before = $this->getJson("/api/pos/shifts/{$shiftKey}/report", $this->deviceHeaders($token))
            ->assertOk()->json('data');
        // float 50000 + cash sales 20000
        $this->assertSame(70000, $before['expected_cash_minor']);
        $this->assertSame(0, $before['refunds_minor']);

        $this->postJson('/api/pos/refunds', $this->refundPayload($order, [
            'shift_client_id' => $shiftKey,
        ]), $this->deviceHeaders($token))->assertCreated();

        $after = $this->getJson("/api/pos/shifts/{$shiftKey}/report", $this->deviceHeaders($token))
            ->assertOk()->json('data');

        $this->assertSame(60000, $after['expected_cash_minor']); // 70000 − 10000 cash back
        $this->assertSame(10000, $after['refunds_minor']);
        $this->assertSame(10000, $after['cash_refunds_minor']);
        $this->assertSame(1, $after['refunds_count']);
    }

    /** A second tenant's claimed terminal, for the isolation assertion. */
    private function claimForeignTerminal(Restaurant $restaurant): string
    {
        $branch = new \App\Models\Branch([
            'name_en' => 'Other', 'code' => 'OTHR', 'supported_order_types' => ['takeaway'],
        ]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $provision = $this->actingAs($owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 1', 'branch_id' => $branch->id])
            ->assertCreated()->json('data');

        $code = $this->actingAs($owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")
            ->assertOk()->json('pairing_code');

        return $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $restaurant->slug,
            'pairing_code' => $code,
            'platform' => 'windows',
            'app_version' => '1.4.2',
            'fingerprint' => 'sha256:other-device',
        ])->assertOk()->json('device_token');
    }
}

<?php

namespace Tests\Feature\Pos;

use App\Models\Branch;
use App\Models\Category;
use App\Models\Charge;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\TaxRule;
use App\Models\TenderType;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Str;

/**
 * POS-BE-006/007/008 (+ BE-A01/§006-P): the money path. The load-bearing
 * assertions are the ones the till cannot negotiate — server pricing wins,
 * a replay returns the identical body (invoice number included) and never a
 * 409, and the invoice sequence never double-issues.
 */
class PosOrdersTest extends PosTestCase
{
    private MenuItem $burger;

    private TenderType $cash;

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

    /** @return array<string,mixed> */
    private function payload(array $overrides = []): array
    {
        // lines/payments replace WHOLESALE — array_replace_recursive would
        // merge an empty override into the defaults and quietly resurrect the
        // default payment.
        $wholesale = array_intersect_key($overrides, ['lines' => 1, 'payments' => 1]);

        return array_merge(array_replace_recursive([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            'created_at' => '2026-09-02T08:00:00+02:00',
            'lines' => [
                ['menu_item_id' => $this->burger->id, 'quantity' => 2, 'name_snapshot' => 'Classic Burger'],
            ],
            'payments' => [
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $this->cash->id, 'amount_minor' => 20000],
            ],
        ], $overrides), $wholesale);
    }

    // ------------------------------------------------------- server pricing

    public function test_prices_come_from_the_server_and_a_wrong_assertion_still_creates_flagged(): void
    {
        $body = $this->postJson('/api/pos/orders', $this->payload([
            'asserted_totals' => [
                'subtotal_minor' => 15000, 'discount_minor' => 0, 'tax_minor' => 0,
                'charges_minor' => 0, 'total_minor' => 15000, // the till priced stale
            ],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        // Server figures, not the client's: 2 × 100.00 EGP = 20000 minor.
        $this->assertSame(20000, $body['totals']['subtotal_minor']);
        $this->assertSame(20000, $body['totals']['total_minor']);
        $this->assertSame('EGP', $body['totals']['currency']);

        // Money was taken, so the order EXISTS — mismatch is a marker on a
        // 201 with both figures for the reconciliation dialog, never an error.
        $this->assertTrue($body['totals_mismatch']);
        $this->assertSame(15000, $body['asserted_totals']['total_minor']);
        $this->assertSame('server', $body['lines'][0]['price_source']);
    }

    public function test_tax_and_charges_follow_the_configured_rules_in_basis_points(): void
    {
        $rule = new TaxRule(['name' => 'VAT', 'rate_bp' => 1400, 'mode' => 'exclusive']);
        $rule->restaurant_id = $this->restaurant->id;
        $rule->save();

        $service = new Charge(['name' => 'Service', 'kind' => 'percent', 'rate_bp' => 1000, 'taxable' => true]);
        $service->restaurant_id = $this->restaurant->id;
        $service->save();

        $body = $this->postJson('/api/pos/orders', $this->payload([
            'payments' => [],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        // base 20000 → service 10% = 2000 (taxable) → VAT 14% on 22000 = 3080.
        $this->assertSame(2000, $body['totals']['charges_minor']);
        $this->assertSame(3080, $body['totals']['tax_minor']);
        $this->assertSame(25080, $body['totals']['total_minor']);
        $this->assertSame('UNPAID', $body['settlement_status']);
    }

    public function test_matching_assertions_carry_no_mismatch_and_no_echo(): void
    {
        $body = $this->postJson('/api/pos/orders', $this->payload([
            'asserted_totals' => [
                'subtotal_minor' => 20000, 'discount_minor' => 0, 'tax_minor' => 0,
                'charges_minor' => 0, 'total_minor' => 20000,
            ],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        $this->assertFalse($body['totals_mismatch']);
        $this->assertArrayNotHasKey('asserted_totals', $body);
        $this->assertSame('PAID', $body['settlement_status']);
    }

    // ------------------------------------------------------- idempotency

    public function test_a_replay_returns_the_identical_body_and_never_409(): void
    {
        $token = $this->token();
        $payload = $this->payload();

        $first = $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $replay = $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($token))
            ->assertOk()->json('data'); // 2xx, NEVER 409 (POS-BE-007)

        $this->assertSame($first, $replay); // id + invoice number included
        $this->assertSame(1, Order::withoutGlobalScopes()->where('channel', 'pos')->count());

        // The replay consumed NO invoice number: the next order takes 000002.
        $next = $this->postJson('/api/pos/orders', $this->payload(), $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $this->assertSame('MAADI-2026-000001', $first['invoice_number']);
        $this->assertSame('MAADI-2026-000002', $next['invoice_number']);
    }

    public function test_the_same_key_with_different_money_is_a_client_bug(): void
    {
        $token = $this->token();
        $payload = $this->payload();

        $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($token))->assertCreated();

        $payload['lines'][0]['quantity'] = 5; // same key, different payload

        $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($token))
            ->assertStatus(422)->assertJsonPath('code', 'IDEMPOTENCY_PAYLOAD_MISMATCH');
    }

    public function test_the_invoice_sequence_is_per_branch(): void
    {
        $token = $this->token();

        $second = new Branch(['name_en' => 'Zamalek', 'code' => 'ZMLK', 'supported_order_types' => ['takeaway']]);
        $second->restaurant_id = $this->restaurant->id;
        $second->save();

        $a = $this->postJson('/api/pos/orders', $this->payload(), $this->deviceHeaders($token))->json('data');
        $b = $this->postJson('/api/pos/orders', $this->payload(['branch_id' => $second->id]), $this->deviceHeaders($token))->json('data');

        // Each branch owns its own counter — MAADI's 000001 and ZMLK's 000001
        // are different documents.
        $this->assertSame('MAADI-2026-000001', $a['invoice_number']);
        $this->assertSame('ZMLK-2026-000001', $b['invoice_number']);
    }

    // ------------------------------------------------------- §006-P

    public function test_paying_more_than_the_bill_is_refused_at_the_door(): void
    {
        // `addPayment` has always refused this; ingest did not, so the one
        // path that could write a ledger state `settlementStatusFrom` has no
        // word for was the unguarded one. Found live on 27 Sep 2026 —
        // BR8-2026-000007, 380.00 of cash recorded against a 360.00 sale,
        // because the till wrote what was TENDERED instead of what it applied.
        $payload = $this->payload();
        $payload['payments'][0]['amount_minor'] = 20000 + 2000;

        $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($this->token()))
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_FAILED');

        $this->assertSame(
            0,
            Order::withoutGlobalScopes()->where('channel', 'pos')->count(),
            'a refused sale writes no order at all',
        );
    }

    public function test_a_settled_sale_is_not_queued_for_confirmation(): void
    {
        // Found live on 27 Sep 2026: six POS sales, all paid at the counter and
        // printed, sat in the dashboard's "new orders" list behind a "Mark
        // received" button — a confirmation nobody could give for money that
        // had already changed hands.
        $order = $this->postJson('/api/pos/orders', $this->payload(), $this->deviceHeaders($this->token()))
            ->assertCreated()->json('data');

        $stored = Order::withoutGlobalScopes()->find($order['id']);
        $this->assertSame('PAID', $order['settlement_status']);
        $this->assertSame('COMPLETED', $stored->status->value);
        $this->assertSame(
            0,
            Order::withoutGlobalScopes()->where('status', 'NEW')->count(),
            'a paid POS sale must not appear in any new-order count',
        );
    }

    public function test_an_unpaid_ticket_stays_open(): void
    {
        // The other half of the rule. A bill rung up against a table and sent
        // to the kitchen is genuinely still open — completing it here would
        // clear the seated-table marker `TableController` draws from NEW.
        $order = $this->postJson('/api/pos/orders', $this->payload(['payments' => []]), $this->deviceHeaders($this->token()))
            ->assertCreated()->json('data');

        $stored = Order::withoutGlobalScopes()->find($order['id']);
        $this->assertSame('UNPAID', $order['settlement_status']);
        $this->assertSame('NEW', $stored->status->value);
    }

    public function test_settling_an_open_bill_later_recomputes_settlement(): void
    {
        $token = $this->token();

        $order = $this->postJson('/api/pos/orders', $this->payload(['payments' => []]), $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $this->assertSame('UNPAID', $order['settlement_status']);

        $payment = [
            'client_transaction_id' => (string) Str::uuid(),
            'tender_type_id' => $this->cash->id,
            'amount_minor' => 20000,
        ];

        // {order} accepts the server id — a second terminal may only know that.
        $paid = $this->postJson("/api/pos/orders/{$order['id']}/payments", $payment, $this->deviceHeaders($token))
            ->assertCreated()->json('data');
        $this->assertSame('PAID', $paid['settlement_status']);
        // And the bill leaves the confirmation queue at the moment it is
        // settled, not only when it arrives settled.
        $this->assertSame(
            'COMPLETED',
            Order::withoutGlobalScopes()->find($order['id'])->status->value,
        );

        // Payment replay: same 2xx body, one row.
        $replay = $this->postJson("/api/pos/orders/{$order['id']}/payments", $payment, $this->deviceHeaders($token))
            ->assertOk()->json('data');
        $this->assertSame($paid['id'], $replay['id']);

        // Overpaying the settled bill is refused with the standard envelope.
        $this->postJson("/api/pos/orders/{$order['id']}/payments", [
            'client_transaction_id' => (string) Str::uuid(),
            'tender_type_id' => $this->cash->id,
            'amount_minor' => 100,
        ], $this->deviceHeaders($token))->assertStatus(422)->assertJsonPath('code', 'VALIDATION_FAILED');
    }

    public function test_split_tender_lands_as_rows(): void
    {
        $card = new TenderType(['name' => 'Card', 'kind' => 'card']);
        $card->restaurant_id = $this->restaurant->id;
        $card->save();

        $body = $this->postJson('/api/pos/orders', $this->payload([
            'payments' => [
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $this->cash->id, 'amount_minor' => 12000],
                ['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $card->id, 'amount_minor' => 8000],
            ],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        $this->assertCount(2, $body['payments']);
        $this->assertSame('PAID', $body['settlement_status']);
    }

    // ------------------------------------------------------- fallbacks + errors

    public function test_a_deleted_item_falls_back_to_its_snapshot_flagged(): void
    {
        $token = $this->token();
        $this->burger->delete(); // soft-deleted mid-outage

        $body = $this->postJson('/api/pos/orders', $this->payload([
            'lines' => [[
                'menu_item_id' => $this->burger->id,
                'quantity' => 1,
                'name_snapshot' => 'Classic Burger',
                'unit_price_minor' => 9500, // the till's asserted price
            ]],
            'payments' => [],
        ]), $this->deviceHeaders($token))->assertCreated()->json('data');

        // Money was taken — honour the sale from the snapshot, flagged.
        $this->assertSame('client_asserted', $body['lines'][0]['price_source']);
        $this->assertSame('Classic Burger', $body['lines'][0]['name']);
        $this->assertSame(9500, $body['totals']['total_minor']);
        // R1: with nothing to resolve, the single snapshot fills both slots.
        $this->assertSame('Classic Burger', $body['lines'][0]['name_ar']);
        $this->assertSame('Classic Burger', $body['lines'][0]['name_en']);
    }

    public function test_a_resolved_line_freezes_both_names_from_the_item_not_the_snapshot(): void
    {
        // R1: the server is the naming authority for a resolved item — it
        // freezes both languages from the item and ignores the till's snapshot.
        $item = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $this->burger->category_id,
            'name_en' => 'Classic Burger',
            'name_ar' => 'برجر كلاسيك',
            'price' => 100.00,
            'discounted_price' => null,
        ]);

        $body = $this->postJson('/api/pos/orders', $this->payload([
            'lines' => [['menu_item_id' => $item->id, 'quantity' => 1, 'name_snapshot' => 'STALE TILL NAME']],
            'payments' => [['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $this->cash->id, 'amount_minor' => 10000]],
        ]), $this->deviceHeaders($this->token()))->assertCreated()->json('data');

        // Response: both languages frozen from the item; snapshot did not win.
        $this->assertSame('برجر كلاسيك', $body['lines'][0]['name_ar']);
        $this->assertSame('Classic Burger', $body['lines'][0]['name_en']);
        $this->assertSame('Classic Burger', $body['lines'][0]['name']);
        $this->assertSame('server', $body['lines'][0]['price_source']);

        // Persisted on the row and in the legacy orders.items JSON projection.
        $row = OrderItem::withoutGlobalScopes()->where('order_id', $body['id'])->firstOrFail();
        $this->assertSame('برجر كلاسيك', $row->name_ar);
        $this->assertSame('Classic Burger', $row->name_en);
        $order = Order::withoutGlobalScopes()->findOrFail($body['id']);
        $this->assertSame('برجر كلاسيك', $order->items[0]['name_ar']);
        $this->assertSame('Classic Burger', $order->items[0]['name_en']);
    }

    public function test_the_v1_relaxation_accepts_no_actor_and_no_shift(): void
    {
        // Every payload in this file omits both — assert the attribution is
        // recorded as terminal-only rather than silently invented.
        $body = $this->postJson('/api/pos/orders', $this->payload(), $this->deviceHeaders($this->token()))
            ->assertCreated()->json('data');

        $order = Order::withoutGlobalScopes()->find($body['id']);
        $this->assertSame('terminal', $order->pos_meta['attribution']);
        $this->assertNull($order->acting_user_id);
        $this->assertNull($order->pos_shift_id);

        // The client's event time is stored as sent — the INSTANT is
        // preserved exactly (serialised in UTC); received_at sits beside it.
        $this->assertTrue(
            Carbon::parse('2026-09-02T08:00:00+02:00')->equalTo($body['created_at']),
        );
        $this->assertNotNull($body['received_at']);
    }

    public function test_a_named_actor_needs_the_verb_the_payload_uses(): void
    {
        $role = new Role(['name' => 'Cashier']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate']])->save(); // no pos.discount
        $cashier = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->postJson('/api/pos/orders', $this->payload([
            'acting_user_id' => $cashier->id,
            'lines' => [[
                'menu_item_id' => $this->burger->id, 'quantity' => 1,
                'name_snapshot' => 'Classic Burger',
                'discount' => ['amount_minor' => 500, 'reason' => 'comp'],
            ]],
            'payments' => [],
        ]), $this->deviceHeaders($this->token()))
            ->assertForbidden()
            ->assertJsonPath('code', 'POS_CAPABILITY_MISSING')
            ->assertJsonPath('details.capability', 'pos.discount');
    }

    public function test_a_foreign_branch_is_invisible_not_forbidden(): void
    {
        $other = Restaurant::factory()->create();
        $foreign = new Branch(['name_en' => 'Foreign', 'code' => 'FRGN']);
        $foreign->restaurant_id = $other->id;
        $foreign->save();

        $this->postJson('/api/pos/orders', $this->payload(['branch_id' => $foreign->id]), $this->deviceHeaders($this->token()))
            ->assertNotFound()->assertJsonPath('code', 'BRANCH_NOT_IN_TENANT');
    }

    public function test_by_client_id_recovers_the_full_body(): void
    {
        $token = $this->token();
        $payload = $this->payload();

        $created = $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($token))->json('data');

        $recovered = $this->getJson('/api/pos/orders/by-client-id/'.$payload['client_transaction_id'], $this->deviceHeaders($token))
            ->assertOk()->json('data');

        $this->assertSame($created, $recovered);

        $this->getJson('/api/pos/orders/by-client-id/'.Str::uuid(), $this->deviceHeaders($token))
            ->assertNotFound();
    }

    // ------------------------------------------------------- plumbing

    private ?string $deviceToken = null;

    private function token(): string
    {
        return $this->deviceToken ??= $this->claimTerminal()['token'];
    }

    public function test_a_pickup_branch_accepts_takeaway_because_they_are_one_thing(): void
    {
        // The onboarding wizard writes `pickup`; the POS sends `takeaway`.
        // Refusing that order would strand every wizard-onboarded branch.
        $this->branch->forceFill(['supported_order_types' => ['pickup']])->save();

        $this->postJson('/api/pos/orders', $this->payload(['order_type' => 'takeaway']),
            $this->deviceHeaders($this->token()))->assertCreated();
    }

    public function test_a_branch_still_refuses_a_type_it_does_not_offer(): void
    {
        $this->branch->forceFill(['supported_order_types' => ['dine_in']])->save();

        $this->postJson('/api/pos/orders', $this->payload(['order_type' => 'delivery']),
            $this->deviceHeaders($this->token()))
            ->assertStatus(422)
            ->assertJsonPath('code', 'VALIDATION_FAILED');
    }
}

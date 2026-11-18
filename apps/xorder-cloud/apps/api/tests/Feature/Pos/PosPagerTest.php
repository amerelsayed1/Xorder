<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Order;
use App\Models\PagerSession;
use App\Models\Restaurant;
use App\Models\TenderType;
use Illuminate\Support\Str;

/**
 * POS-BE-035 (PROPOSED), guest paging shared QR: the till's side. The client
 * scans the one standing QR and reads a code out; the cashier types it with the
 * order; the cloud ties the phone to that order. A bad code never changes the
 * sale (BR-7).
 */
class PosPagerTest extends PosTestCase
{
    private MenuItem $burger;

    private TenderType $cash;

    private ?string $deviceToken = null;

    protected function setUp(): void
    {
        parent::setUp();

        $this->restaurant->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => true]);
        $this->restaurant->forceFill(['slug' => 'demo'])->save();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $this->burger = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id, 'category_id' => $category->id,
            'price' => 100.00, 'discounted_price' => null,
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

    /** @return array<string,mixed> */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'client_transaction_id' => (string) Str::uuid(),
            'branch_id' => $this->branch->id,
            'order_type' => 'takeaway',
            // Now: the order-number page only reads orders newer than its 48 h window.
            'created_at' => now()->toIso8601String(),
            'lines' => [['menu_item_id' => $this->burger->id, 'quantity' => 2, 'name_snapshot' => 'Classic Burger']],
            'payments' => [['client_transaction_id' => (string) Str::uuid(), 'tender_type_id' => $this->cash->id, 'amount_minor' => 20000]],
        ], $overrides);
    }

    private function sale(array $payload)
    {
        return $this->postJson('/api/pos/orders', $payload, $this->deviceHeaders($this->token()));
    }

    /** What a client's phone does: scan the QR, get a code and a secret. */
    private function scan(string $slug = 'demo'): array
    {
        return $this->postJson("/api/public/restaurants/{$slug}/pager-sessions")->assertCreated()->json('data');
    }

    private function peek(string $code)
    {
        return $this->getJson('/api/pos/pager/'.rawurlencode($code), $this->deviceHeaders($this->token()));
    }

    // ---------------------------------------------------------- the check

    public function test_the_peek_says_whether_a_code_is_open(): void
    {
        $session = $this->scan();

        $this->peek($session['code'])->assertOk()->assertJsonPath('data.open', true);
        $this->peek($session['code'] === '1234' ? '4321' : '1234')
            ->assertNotFound()->assertJsonPath('code', 'PAGER_CODE_NOT_FOUND');
    }

    // AC-12 (the server half: the till folds digits too, this is the safety net)
    public function test_arabic_indic_digits_in_the_order_are_read_as_the_same_code(): void
    {
        $session = $this->scan();
        $arabic = strtr($session['code'], ['0' => '٠', '1' => '١', '2' => '٢', '3' => '٣', '4' => '٤', '5' => '٥', '6' => '٦', '7' => '٧', '8' => '٨', '9' => '٩']);

        $this->sale($this->payload(['pager_code' => $arabic]))
            ->assertCreated()->assertJsonPath('pager.status', 'paired');
    }

    // AC-6
    public function test_a_code_of_another_restaurant_is_not_found(): void
    {
        $other = Restaurant::factory()->create(['slug' => 'other']);
        $other->features()->create(['feature_key' => 'guest_paging', 'is_enabled' => true]);
        $theirs = $this->scan('other');

        $this->peek($theirs['code'])->assertNotFound();

        $res = $this->sale($this->payload(['pager_code' => $theirs['code']]))->assertCreated();
        $res->assertJsonPath('pager.status', 'not_found');
        $this->assertNull(PagerSession::query()->whereNotNull('bound_at')->first(), 'nothing was paired');
    }

    // ---------------------------------------------------- pairing an order

    // AC-2
    public function test_a_code_typed_with_the_order_pairs_the_phone_to_it(): void
    {
        $session = $this->scan();

        $res = $this->sale($this->payload(['pager_code' => $session['code']]))->assertCreated();
        $res->assertJsonPath('pager.status', 'paired');

        $order = Order::query()->findOrFail($res->json('data.id'));
        $this->assertNotNull($order->pickup_token);
        $this->assertSame('PREPARING', $order->pickup_status->value);
        $this->assertSame((string) $order->invoice_number, $order->pickup_display_ref);

        // The phone learns the order's token...
        $current = $this->getJson('/api/public/restaurants/demo/pager-sessions/current', ['X-Pager-Secret' => $session['secret']])
            ->assertOk();
        $current->assertJsonPath('data.state', 'bound');
        $this->assertSame($order->pickup_token, $current->json('data.tracking_token'));
        $this->assertArrayNotHasKey('code', $current->json('data'));

        // ...and the existing order-number page reads it: the slip's number, preparing.
        $this->getJson('/api/public/orders/track/'.$order->pickup_token)
            ->assertOk()
            ->assertJsonPath('data.status', 'PREPARING')
            ->assertJsonPath('data.ref', (string) $order->invoice_number);
    }

    // AC-3
    public function test_a_code_pairs_one_order_only(): void
    {
        $session = $this->scan();

        $this->sale($this->payload(['pager_code' => $session['code']]))->assertCreated()->assertJsonPath('pager.status', 'paired');
        $second = $this->sale($this->payload(['pager_code' => $session['code']]))->assertCreated();

        $second->assertJsonPath('pager.status', 'not_found');
        $this->assertNull(Order::query()->findOrFail($second->json('data.id'))->pickup_token);
        $this->assertSame(1, PagerSession::query()->whereNotNull('order_id')->count());
    }

    // AC-4, and the proof that the code stays out of the idempotency hash
    public function test_a_replay_is_still_a_replay_and_pairs_once(): void
    {
        $session = $this->scan();
        $payload = $this->payload(['pager_code' => $session['code']]);

        $first = $this->sale($payload)->assertCreated();
        $replay = $this->sale($payload)->assertOk();
        $this->assertSame($first->json('data.id'), $replay->json('data.id'));
        $replay->assertJsonPath('pager.status', 'paired');

        // The same order again, a different code (or none): still a replay, never a 422.
        $this->sale(array_merge($payload, ['pager_code' => '0000']))->assertOk();
        $without = $payload;
        unset($without['pager_code']);
        $this->sale($without)->assertOk()->assertJsonMissingPath('pager');

        $this->assertSame(1, PagerSession::query()->whereNotNull('order_id')->count());
    }

    // AC-5, BR-7
    public function test_a_wrong_or_expired_code_never_blocks_the_sale(): void
    {
        $unknown = $this->sale($this->payload(['pager_code' => '4821']))->assertCreated();
        $unknown->assertJsonPath('pager.status', 'not_found');
        $this->assertNull(Order::query()->findOrFail($unknown->json('data.id'))->pickup_token);

        $session = $this->scan();
        PagerSession::query()->update(['expires_at' => now()->subMinute()]);
        $this->sale($this->payload(['pager_code' => $session['code']]))
            ->assertCreated()->assertJsonPath('pager.status', 'expired');

        $this->sale($this->payload(['pager_code' => 'abc']))->assertCreated()->assertJsonPath('pager.status', 'not_found');
    }

    // AC-7
    public function test_an_order_that_is_not_paged_is_not_paired(): void
    {
        $session = $this->scan();

        $this->sale($this->payload(['order_type' => 'dine_in', 'pager_code' => $session['code']]))
            ->assertCreated()->assertJsonPath('pager.status', 'not_eligible');

        $this->assertSame(0, PagerSession::query()->whereNotNull('order_id')->count());
        $this->peek($session['code'])->assertOk(); // the code is still open for the right order
    }

    // AC-15
    public function test_nothing_pairs_when_the_restaurant_does_not_have_the_feature(): void
    {
        $session = $this->scan();
        $this->restaurant->features()->where('feature_key', 'guest_paging')->update(['is_enabled' => false]);
        $this->restaurant->unsetRelation('features');

        $this->peek($session['code'])->assertNotFound();
        $this->sale($this->payload(['pager_code' => $session['code']]))
            ->assertCreated()->assertJsonPath('pager.status', 'not_eligible');
    }

    // Regression: an order without a code looks exactly as before.
    public function test_an_order_without_a_code_has_no_pager_in_its_answer(): void
    {
        $this->sale($this->payload())->assertCreated()->assertJsonMissingPath('pager');
    }

    // POS-BE-035: the bootstrap key
    public function test_the_bootstrap_says_whether_paging_is_on(): void
    {
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($this->token()))
            ->assertOk()->assertJsonPath('restaurant.guest_paging', true);

        $this->restaurant->features()->where('feature_key', 'guest_paging')->update(['is_enabled' => false]);

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($this->token()))
            ->assertOk()->assertJsonPath('restaurant.guest_paging', false);
    }
}

<?php

namespace Tests\Feature\Pos;

use App\Enums\BillRequestStatus;
use App\Enums\OrderStatus;
use App\Models\BillRequest;
use App\Models\Branch;
use App\Models\Order;
use App\Models\Restaurant;
use App\Support\TenantContext;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * POS-BE-033 — the till's incoming feed of online orders and table requests,
 * and accept / reject / handled. SQLite cannot prove lockForUpdate: the two-till
 * race is exercised serially (the second call sees the committed winner).
 */
class PosIncomingTest extends PosTestCase
{
    private string $token;

    protected function setUp(): void
    {
        parent::setUp();
        $this->token = $this->claimTerminal()['token'];
        $this->switchOn($this->branch);
    }

    private function switchOn(Branch $branch, bool $on = true): void
    {
        DB::table('branches')->where('id', $branch->id)->update(['online_orders_on_pos' => $on]);
    }

    private function inTenant(Restaurant $r, callable $fn): mixed
    {
        TenantContext::overrideId($r->id);
        try {
            return $fn();
        } finally {
            TenantContext::clearOverride();
        }
    }

    private function makeOrder(?Restaurant $r = null, ?Branch $b = null, array $attrs = []): Order
    {
        $r ??= $this->restaurant;
        $b ??= $this->branch;

        return $this->inTenant($r, function () use ($r, $b, $attrs) {
            $o = new Order(array_merge([
                'status' => OrderStatus::NEW,
                'items' => [['name' => 'Burger', 'qty' => 1, 'unit_price' => 100, 'line_total' => 100]],
                'total' => 100,
                'currency' => 'EGP',
                'order_type' => 'takeaway',
                'source' => 'system',
                'branch_id' => $b->id,
                'customer_name' => 'Sara',
                'customer_phone' => '01012345678',
            ], $attrs));
            $o->restaurant_id = $r->id;
            $o->save();

            return $o;
        });
    }

    private function makeRequest(?Restaurant $r = null, ?Branch $b = null): BillRequest
    {
        $r ??= $this->restaurant;
        $b ??= $this->branch;

        return $this->inTenant($r, function () use ($r, $b) {
            $x = new BillRequest([
                'branch_id' => $b->id,
                'public_token' => BillRequest::generateToken(),
                'status' => BillRequestStatus::REQUESTED,
                'requested_at' => now(),
            ]);
            $x->restaurant_id = $r->id;
            $x->save();

            return $x;
        });
    }

    private function feed(?string $cursor = null, ?string $token = null, array $headers = [])
    {
        $url = '/api/pos/incoming'.($cursor ? '?cursor='.urlencode($cursor) : '');

        return $this->getJson($url, $this->deviceHeaders($token ?? $this->token) + $headers);
    }

    /** @return array<string,mixed> */
    private function other(): array
    {
        $r = Restaurant::factory()->create(['currency' => 'EGP']);
        $r->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $b = new Branch(['name_en' => 'Other', 'code' => 'OTH', 'supported_order_types' => ['takeaway']]);
        $b->restaurant_id = $r->id;
        $b->save();

        return [$r, $b];
    }

    // ── feed ────────────────────────────────────────────────────────────

    public function test_first_read_returns_open_orders_and_requests_with_server_lines(): void
    {
        $o = $this->makeOrder();
        $r = $this->makeRequest();

        $res = $this->feed()->assertOk();
        $events = collect($res->json('data.events'));

        $this->assertCount(2, $events);
        $order = $events->firstWhere('kind', 'online_order');
        $this->assertSame($o->id, $order['id']);
        $this->assertSame('new', $order['state']);
        $this->assertSame('Burger', $order['items'][0]['name']);
        $this->assertSame($r->id, $events->firstWhere('kind', 'table_request')['id']);
        $this->assertNotEmpty($res->json('data.cursor'));
    }

    public function test_each_event_is_returned_once_and_idle_reads_are_304(): void
    {
        $this->makeOrder();
        $first = $this->feed()->assertOk();
        $cursor = $first->json('data.cursor');

        // Nothing changed: same cursor → empty events, and the repeat is a bodyless 304.
        $second = $this->feed($cursor)->assertOk();
        $this->assertSame([], $second->json('data.events'));
        $this->assertSame($cursor, $second->json('data.cursor'));
        $etag = $second->headers->get('ETag');
        $this->assertNotEmpty($etag);

        $this->getJson('/api/pos/incoming?cursor='.urlencode($cursor), $this->deviceHeaders($this->token) + ['If-None-Match' => $etag])
            ->assertStatus(304);
    }

    public function test_changes_in_the_cursors_own_second_arrive_once_and_none_are_lost(): void
    {
        // Fixed second, so the test never straddles a clock tick.
        $t0 = now()->subMinute()->startOfSecond();
        $a = $this->makeOrder();
        $x = $this->makeOrder();
        DB::table('orders')->whereIn('id', [$a->id, $x->id])->update(['updated_at' => $t0]);

        $cursor = $this->feed()->json('data.cursor');

        // In that same second: a NEW row, and a state change on an already-seen
        // row with a LOWER id than the new one — a plain (ts,id) cursor loses x.
        $b = $this->makeOrder();
        $this->postJson("/api/pos/online-orders/{$x->id}/accept", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($this->token))->assertOk();
        DB::table('orders')->whereIn('id', [$b->id, $x->id])->update(['updated_at' => $t0]);

        $events = collect($this->feed($cursor)->json('data.events'))->keyBy('id');
        $this->assertSame([$x->id, $b->id], $events->keys()->sort()->values()->all());
        $this->assertSame('accepted', $events[$x->id]['state']);

        // `a` never changed: not repeated. And a second read from the new cursor is empty.
        $this->assertArrayNotHasKey($a->id, $events->all());
        $next = $this->feed($cursor)->json('data.cursor');
        $this->assertSame([], $this->feed($next)->json('data.events'));
    }

    public function test_terminal_states_reach_the_other_tills_after_a_cursor(): void
    {
        $o = $this->makeOrder();
        $cursor = $this->feed()->json('data.cursor');

        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => (string) Str::uuid(), 'reason' => 'Sold out'], $this->deviceHeaders($this->token))->assertOk();

        $ev = $this->feed($cursor)->json('data.events');
        $this->assertSame('rejected', $ev[0]['state']);
        $this->assertSame('Sold out', $ev[0]['reject_reason']);
    }

    public function test_feed_is_empty_and_actions_refused_while_the_branch_switch_is_off(): void
    {
        $o = $this->makeOrder();
        $this->switchOn($this->branch, false);

        $this->assertSame([], $this->feed()->assertOk()->json('data.events'));
        $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($this->token))
            ->assertStatus(403)->assertJson(['code' => 'ONLINE_ORDERS_NOT_ON_POS']);
    }

    public function test_feed_records_last_feed_and_app_version(): void
    {
        $terminal = $this->claimTerminal(['fingerprint' => 'sha256:second'])['terminal'];
        $token = $this->claimTerminal(['fingerprint' => 'sha256:third'])['token'];

        $this->feed(null, $token, ['X-App-Version' => '9.9.9'])->assertOk();

        $stamped = \App\Models\PosTerminal::withoutGlobalScopes()->where('device_token_hash', \App\Support\DeviceToken::hash($token))->first();
        $this->assertNotNull($stamped->last_feed_at);
        $this->assertSame('9.9.9', $stamped->app_version);
    }

    public function test_a_garbage_cursor_is_422_and_no_token_is_401(): void
    {
        $this->feed('not-a-cursor')->assertStatus(422)->assertJson(['code' => 'INVALID_CURSOR']);
        $bad = rtrim(strtr(base64_encode(json_encode(['o' => ['ts' => "'; drop", 'seen' => []], 'b' => ['ts' => null, 'seen' => []]])), '+/', '-_'), '=');
        $this->feed($bad)->assertStatus(422)->assertJson(['code' => 'INVALID_CURSOR']);
        $this->getJson('/api/pos/incoming')->assertStatus(401);
    }

    // ── tenant and branch boundaries (AC-15) ────────────────────────────

    public function test_other_tenants_and_other_branches_are_never_seen_or_touched(): void
    {
        [$r2, $b2] = $this->other();
        $foreign = $this->makeOrder($r2, $b2);
        $foreignReq = $this->makeRequest($r2, $b2);

        $second = new Branch(['name_en' => 'Zamalek', 'code' => 'ZAM', 'supported_order_types' => ['takeaway']]);
        $second->restaurant_id = $this->restaurant->id;
        $second->save();
        $sibling = $this->makeOrder(null, $second);

        $this->assertSame([], $this->feed()->json('data.events'));

        $h = $this->deviceHeaders($this->token);
        foreach ([$foreign->id, $sibling->id] as $id) {
            $this->postJson("/api/pos/online-orders/{$id}/accept", ['client_request_id' => (string) Str::uuid()], $h)->assertStatus(404);
            $this->postJson("/api/pos/online-orders/{$id}/reject", ['client_request_id' => (string) Str::uuid(), 'reason' => 'x'], $h)->assertStatus(404);
        }
        $this->postJson("/api/pos/table-requests/{$foreignReq->id}/handled", ['client_request_id' => (string) Str::uuid()], $h)->assertStatus(404);

        $this->assertNull(DB::table('orders')->where('id', $foreign->id)->value('accepted_at'));
    }

    public function test_a_running_dine_in_bill_is_never_offered_to_the_till(): void
    {
        $o = $this->makeOrder();
        $now = now();
        $r = $this->restaurant->id;
        $area = DB::table('dining_areas')->insertGetId(['restaurant_id' => $r, 'branch_id' => $this->branch->id, 'type' => 'indoor', 'created_at' => $now, 'updated_at' => $now]);
        $table = DB::table('dining_tables')->insertGetId(['restaurant_id' => $r, 'branch_id' => $this->branch->id, 'dining_area_id' => $area, 'label' => '1', 'public_token' => 'tok-1', 'created_at' => $now, 'updated_at' => $now]);
        $visit = DB::table('table_visits')->insertGetId(['restaurant_id' => $r, 'branch_id' => $this->branch->id, 'table_id' => $table, 'status' => 'OPEN', 'opened_at' => $now, 'created_at' => $now, 'updated_at' => $now]);
        DB::table('orders')->where('id', $o->id)->update(['table_visit_id' => $visit]);

        $this->assertSame([], $this->feed()->json('data.events'));
        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => (string) Str::uuid(), 'reason' => 'x'], $this->deviceHeaders($this->token))
            ->assertStatus(404);
        $this->assertSame('NEW', DB::table('orders')->where('id', $o->id)->value('status'));
    }

    public function test_pos_and_whatsapp_orders_are_not_online_orders_for_the_till(): void
    {
        $this->makeOrder(null, null, ['source' => 'pos']);
        $this->makeOrder(null, null, ['source' => 'whatsapp']);

        $this->assertSame([], $this->feed()->json('data.events'));
    }

    // ── accept / reject / handled ───────────────────────────────────────

    public function test_accept_is_idempotent_for_the_same_request_and_409_for_a_second_till(): void
    {
        $o = $this->makeOrder();
        $h = $this->deviceHeaders($this->token);
        $req = (string) Str::uuid();

        $first = $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => $req], $h)->assertOk();
        $this->assertSame('accepted', $first->json('data.state'));
        $at = DB::table('orders')->where('id', $o->id)->value('accepted_at');

        $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => $req], $h)->assertOk();
        $this->assertSame($at, DB::table('orders')->where('id', $o->id)->value('accepted_at'));

        // A second till of the same branch loses the race.
        $token2 = $this->claimTerminal(['fingerprint' => 'sha256:till-two'])['token'];
        $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($token2))
            ->assertStatus(409)->assertJson(['code' => 'ALREADY_ACCEPTED']);

        // And cannot reject what was accepted.
        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => (string) Str::uuid(), 'reason' => 'x'], $this->deviceHeaders($token2))
            ->assertStatus(409)->assertJson(['code' => 'ALREADY_ACCEPTED']);

        $this->assertSame('NEW', DB::table('orders')->where('id', $o->id)->value('status'), 'accepted is not a status');
    }

    public function test_reject_cancels_the_order_stores_the_reason_and_the_diner_status_shows_it_without_the_reason(): void
    {
        $o = $this->makeOrder();
        $h = $this->deviceHeaders($this->token);
        $req = (string) Str::uuid();

        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => $req, 'reason' => 'Kitchen closed'], $h)
            ->assertOk()->assertJsonPath('data.state', 'rejected');
        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => $req, 'reason' => 'Kitchen closed'], $h)->assertOk();

        $this->assertSame('CANCELLED', DB::table('orders')->where('id', $o->id)->value('status'));

        $this->getJson("/api/public/restaurants/{$this->restaurant->slug}/orders/{$o->id}/status")
            ->assertOk()
            ->assertJsonPath('data.status', 'CANCELLED')
            ->assertJsonPath('data.rejected', true)
            ->assertJsonMissingPath('data.reject_reason');

        $token2 = $this->claimTerminal(['fingerprint' => 'sha256:till-two'])['token'];
        $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($token2))
            ->assertStatus(409)->assertJson(['code' => 'ALREADY_REJECTED']);
    }

    public function test_an_order_already_completed_or_cancelled_cannot_be_accepted(): void
    {
        $o = $this->makeOrder(null, null, ['status' => OrderStatus::COMPLETED]);

        $this->postJson("/api/pos/online-orders/{$o->id}/accept", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($this->token))
            ->assertStatus(409)->assertJson(['code' => 'ORDER_NOT_PENDING']);
    }

    public function test_table_request_handled_closes_once_and_is_idempotent(): void
    {
        $x = $this->makeRequest();
        $h = $this->deviceHeaders($this->token);
        $req = (string) Str::uuid();

        $this->postJson("/api/pos/table-requests/{$x->id}/handled", ['client_request_id' => $req], $h)
            ->assertOk()->assertJsonPath('data.state', 'handled');
        $this->postJson("/api/pos/table-requests/{$x->id}/handled", ['client_request_id' => $req], $h)->assertOk();

        $token2 = $this->claimTerminal(['fingerprint' => 'sha256:till-two'])['token'];
        $this->postJson("/api/pos/table-requests/{$x->id}/handled", ['client_request_id' => (string) Str::uuid()], $this->deviceHeaders($token2))
            ->assertStatus(409)->assertJson(['code' => 'ALREADY_HANDLED']);
    }

    public function test_validation_and_unknown_ids(): void
    {
        $o = $this->makeOrder();
        $h = $this->deviceHeaders($this->token);

        $this->postJson("/api/pos/online-orders/{$o->id}/accept", [], $h)->assertStatus(422);
        $this->postJson("/api/pos/online-orders/{$o->id}/reject", ['client_request_id' => (string) Str::uuid()], $h)->assertStatus(422);
        $this->postJson('/api/pos/online-orders/999999/accept', ['client_request_id' => (string) Str::uuid()], $h)->assertStatus(404);
    }

    public function test_a_revoked_terminal_is_refused(): void
    {
        $t = $this->claimTerminal(['fingerprint' => 'sha256:to-revoke']);
        $this->actingAs($this->owner)->postJson("/api/dashboard/pos/terminals/{$t['terminal']->id}/revoke")->assertOk();
        $this->app['auth']->forgetGuards();

        $this->feed(null, $t['token'])->assertStatus(403)->assertJson(['code' => 'TERMINAL_REVOKED']);
    }

    public function test_the_status_endpoint_is_unchanged_for_orders_never_rejected(): void
    {
        $o = $this->makeOrder();
        $res = $this->getJson("/api/public/restaurants/{$this->restaurant->slug}/orders/{$o->id}/status")->assertOk();
        $this->assertSame(['status' => 'NEW'], $res->json('data'));
    }
}

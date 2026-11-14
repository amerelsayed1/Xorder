<?php

namespace Tests\Feature\Pos;

use App\Models\Category;
use App\Models\DiningArea;
use App\Models\DiningTable;
use App\Models\MenuItem;
use App\Models\Plan;
use App\Models\PosPairingCode;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\Role;
use App\Models\User;
use App\Services\LicenceIssuer;
use App\Support\PosPin;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * POS-BE-011 / 022 / 023 / 016: provision → pairing code → claim → device
 * token → bootstrap → heartbeat, with the idempotency and failure semantics
 * the contracts pin down.
 */
class PosProvisioningTest extends PosTestCase
{
    // ------------------------------------------------------------- claim

    public function test_the_full_path_a_flow_provisions_claims_and_bootstraps(): void
    {
        ['token' => $token, 'terminal' => $terminal, 'response' => $response] = $this->claimTerminal();

        $this->assertStringStartsWith('xdt_', $token);
        $this->assertSame(PosTerminal::STATE_ACTIVE, $terminal->state);
        $this->assertNotNull($terminal->claimed_at);
        // The token is stored only as an HMAC — never plaintext.
        $this->assertNotNull($terminal->device_token_hash);
        $this->assertNotSame($token, $terminal->device_token_hash);

        // The claim response carries the FULL bundle: no second call needed.
        $bootstrap = $response['bootstrap'];
        $this->assertSame($this->restaurant->slug, $bootstrap['restaurant']['slug']);
        $this->assertSame('EGP', $bootstrap['restaurant']['currency']);
        $this->assertSame(2, $bootstrap['restaurant']['exponent']);
        $this->assertSame(['pos'], $bootstrap['modules']);
        $this->assertSame($terminal->terminal_id, $bootstrap['terminal']['id']);
        $this->assertIsInt($bootstrap['config_version']);
        $this->assertArrayHasKey('server_time', $bootstrap);
    }

    public function test_a_replayed_claim_from_the_same_device_returns_the_identical_response(): void
    {
        ['token' => $token, 'response' => $first, 'pairing_code' => $code] = $this->claimTerminal();

        $replay = $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => $code,
            'platform' => 'windows',
            'app_version' => '1.4.2',
            'fingerprint' => 'sha256:test-device',
        ])->assertOk()->json();

        // Byte-identical: same device token, same terminal — never a second one.
        $this->assertSame($token, $replay['device_token']);
        $this->assertSame($first['terminal']['id'], $replay['terminal']['id']);
        $this->assertSame(1, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_a_used_code_from_a_different_device_is_refused_with_its_own_code(): void
    {
        ['pairing_code' => $code] = $this->claimTerminal();

        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => $code,
            'fingerprint' => 'sha256:SOME-OTHER-MACHINE',
        ])->assertStatus(422)->assertJsonPath('code', 'PAIRING_CODE_USED');
    }

    public function test_unknown_and_expired_codes_fail_distinctly(): void
    {
        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => 'ZZZZ-ZZZZ',
        ])->assertStatus(422)->assertJsonPath('code', 'PAIRING_CODE_INVALID');

        // Issue a code, then age it past its TTL.
        $this->claimTerminal(); // consumes one; issue a fresh terminal + code
        $provision = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 2', 'branch_id' => $this->branch->id])
            ->json('data');
        $code = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")
            ->json('pairing_code');

        PosPairingCode::withoutGlobalScopes()->latest('id')->first()
            ->forceFill(['expires_at' => now()->subMinute()])->save();

        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => $code,
        ])->assertStatus(422)->assertJsonPath('code', 'PAIRING_CODE_EXPIRED');
    }

    public function test_regenerating_the_pairing_code_kills_the_old_one(): void
    {
        $provision = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 1', 'branch_id' => $this->branch->id])
            ->json('data');

        $old = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")->json('pairing_code');
        $new = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$provision['id']}/pairing-code")->json('pairing_code');

        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug, 'pairing_code' => $old,
        ])->assertStatus(422)->assertJsonPath('code', 'PAIRING_CODE_EXPIRED');

        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug, 'pairing_code' => $new,
        ])->assertOk();
    }

    // ------------------------------------------------------- Path B

    public function test_path_b_register_works_for_staff_holding_pos_provision_and_replays_idempotently(): void
    {
        $role = new Role(['name' => 'Installer']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate', 'pos.provision']])->save();
        $installer = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $payload = [
            'client_transaction_id' => (string) Str::uuid(),
            'name' => 'Back Office Till',
            'branch_id' => $this->branch->id,
            'platform' => 'macos',
        ];

        $first = $this->actingAs($installer)->postJson('/api/pos/terminals/register', $payload)
            ->assertCreated()->json();
        $replay = $this->actingAs($installer)->postJson('/api/pos/terminals/register', $payload)
            ->assertOk()->json();

        $this->assertSame($first['device_token'], $replay['device_token']);
        $this->assertSame(1, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_register_requires_the_pos_provision_verb(): void
    {
        $role = new Role(['name' => 'Cashier']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate']])->save();
        $cashier = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($cashier)->postJson('/api/pos/terminals/register', [
            'client_transaction_id' => (string) Str::uuid(),
            'name' => 'Rogue', 'branch_id' => $this->branch->id,
        ])->assertForbidden();
    }

    // ------------------------------------------------------- device token

    public function test_rotation_issues_a_new_token_and_honours_the_old_one_for_the_overlap(): void
    {
        ['token' => $old] = $this->claimTerminal();

        $new = $this->postJson('/api/pos/terminals/rotate-token', [], $this->deviceHeaders($old))
            ->assertOk()->json('device_token');

        $this->assertNotSame($old, $new);

        // Both work during the overlap — a till that crashed mid-rotation is
        // not bricked.
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($new))->assertOk();
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($old))->assertOk();

        // Past the overlap the old token dies.
        $this->travel(25)->hours();
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($old))
            ->assertUnauthorized()->assertJsonPath('code', 'DEVICE_TOKEN_INVALID');
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($new))->assertOk();
    }

    public function test_garbage_and_revoked_credentials_fail_with_distinct_codes(): void
    {
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders('xdt_'.str_repeat('0', 64)))
            ->assertUnauthorized()->assertJsonPath('code', 'DEVICE_TOKEN_INVALID');

        ['token' => $token, 'terminal' => $terminal] = $this->claimTerminal();

        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$terminal->id}/revoke")
            ->assertOk();

        // Revoked ≠ unknown: the client re-pairs on 401 but tells the manager
        // on TERMINAL_REVOKED.
        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))
            ->assertForbidden()->assertJsonPath('code', 'TERMINAL_REVOKED');
    }

    public function test_the_feature_gate_rides_the_device_path_with_its_own_code(): void
    {
        ['token' => $token] = $this->claimTerminal();

        $this->restaurant->features()->where('feature_key', 'pos')->update(['is_enabled' => false]);

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))
            ->assertForbidden()->assertJsonPath('code', 'POS_FEATURE_DISABLED');

        // ...but the heartbeat still lands: a lapsed feature must not silence
        // the fleet view (POS-BE-022).
        $this->postJson('/api/pos/terminals/heartbeat', ['pending_count' => 3], $this->deviceHeaders($token))
            ->assertOk();
    }

    // ------------------------------------------------------- bootstrap

    public function test_the_bundle_serialises_the_frozen_key_map(): void
    {
        // Floor + staff + catalog fixtures.
        $area = new DiningArea(['branch_id' => $this->branch->id, 'name_en' => 'Terrace', 'is_active' => true]);
        $area->restaurant_id = $this->restaurant->id;
        $area->save();
        $table = new DiningTable([
            'branch_id' => $this->branch->id, 'dining_area_id' => $area->id,
            'label' => 'T1', 'seats_count' => 4, 'is_active' => true,
        ]);
        $table->restaurant_id = $this->restaurant->id;
        $table->public_token = DiningTable::generateToken();
        $table->save();

        $category = Category::factory()->create(['restaurant_id' => $this->restaurant->id]);
        $item = MenuItem::factory()->create([
            'restaurant_id' => $this->restaurant->id,
            'category_id' => $category->id,
            'price' => 100.50,
            'discounted_price' => null,
        ]);

        $pair = PosPin::make('4829');
        $this->owner->forceFill(['pos_pin_salt' => $pair['salt'], 'pos_pin_hash' => $pair['hash']])->save();

        ['token' => $token] = $this->claimTerminal();

        $bundle = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))
            ->assertOk()
            ->assertHeader('X-Config-Version')
            ->json();

        // tables[] — the 2026-09-02 amendment, terminal's branch only.
        $this->assertSame('T1', $bundle['tables'][0]['label']);
        $this->assertSame(4, $bundle['tables'][0]['seats']);
        $this->assertSame('Terrace', $bundle['tables'][0]['area_name']);

        // catalog items: INT minor units (a float here drops the product on
        // the client — tested behaviour on their side) + resolved group ids.
        $row = collect($bundle['catalog']['items']['data'])->firstWhere('id', $item->id);
        $this->assertSame(10050, $row['price_minor']);
        $this->assertNull($row['discounted_price_minor']);
        $this->assertSame([], $row['option_group_ids']);
        $this->assertTrue($bundle['catalog']['items']['complete']);
        $this->assertFalse($bundle['catalog']['option_groups']['complete']);

        // staff[]: the PBKDF2 pin block — the ONE wire it travels on.
        $ownerRow = collect($bundle['staff'])->firstWhere('id', $this->owner->id);
        $this->assertSame('pbkdf2_sha256', $ownerRow['pin']['algorithm']);
        $this->assertSame(120000, $ownerRow['pin']['iterations']);
        $this->assertSame($pair['salt'], $ownerRow['pin']['salt']);
        $this->assertContains('pos.operate', $ownerRow['capabilities']);

        // money + invoice blocks present with defaults.
        $this->assertSame([], $bundle['money']['tax_rules']);
        $this->assertSame('branch_code', $bundle['invoice']['prefix_source']);

        // DIS-1: database block only here, null for cloud.
        $this->assertNull($bundle['endpoints']['database_host']);
    }

    public function test_bootstrap_honours_if_none_match_with_a_304(): void
    {
        ['token' => $token] = $this->claimTerminal();

        $response = $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk();
        $etag = $response->headers->get('ETag');

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token) + ['If-None-Match' => $etag])
            ->assertStatus(304);

        // A bundle-shaped write bumps the version and the ETag stops matching.
        $this->actingAs($this->owner)->postJson('/api/dashboard/tender-types', [
            'name' => 'Cash', 'kind' => 'cash',
        ])->assertCreated();

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token) + ['If-None-Match' => $etag])
            ->assertOk();
    }

    // ------------------------------------------------------- heartbeat

    public function test_the_heartbeat_returns_the_five_agreed_fields_and_records_the_telemetry(): void
    {
        ['token' => $token, 'terminal' => $terminal] = $this->claimTerminal();

        $body = $this->postJson('/api/pos/terminals/heartbeat', [
            'app_version' => '1.5.0',
            'pending_count' => 37,
            'oldest_pending_at' => '2026-09-02T09:14:00Z',
            'shift_open' => true,
            'clock_offset_seconds' => -4,
        ], $this->deviceHeaders($token))->assertOk()->json();

        // Exactly the agreed response — one heartbeat serves clock skew, the
        // offline window, the renewal banner, config polling and revocation.
        $this->assertSame(
            ['server_time', 'site_last_contact_at', 'licence_expires_at', 'config_version', 'terminal_status'],
            array_keys($body),
        );
        $this->assertSame('active', $body['terminal_status']);
        $this->assertIsInt($body['config_version']);

        $terminal->refresh();
        $this->assertSame(37, $terminal->pending_count);
        $this->assertSame(-4, $terminal->clock_offset_seconds);
        $this->assertNotNull($terminal->last_seen_at);
        $this->assertSame('1.5.0', $terminal->app_version);
    }

    // ------------------------------------------------------- seats + fleet

    public function test_path_b_register_is_gated_by_the_same_seat_count(): void
    {
        // Self-service registration must not be a way around the limit that
        // the pairing-code path enforces.
        $this->planWithSeats(1);
        $this->claimTerminal();

        $role = new Role(['name' => 'Installer']);
        $role->restaurant_id = $this->restaurant->id;
        $role->forceFill(['capabilities' => ['pos.operate', 'pos.provision']])->save();
        $installer = User::factory()->staff($this->restaurant->id, $role->id)->create();

        $this->actingAs($installer)->postJson('/api/pos/terminals/register', [
            'client_transaction_id' => (string) Str::uuid(),
            'name' => 'Back Office Till',
            'branch_id' => $this->branch->id,
        ])->assertStatus(422)->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT');

        // Nothing was provisioned by the refusal — a refused register leaves
        // no half-built terminal squatting the fleet list.
        $this->assertSame(1, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_fleet_views_are_super_admin_only_and_cross_tenant(): void
    {
        $this->claimTerminal();

        $other = Restaurant::factory()->create();
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);

        $sa = User::factory()->superAdmin()->create();

        $rows = $this->actingAs($sa)->getJson('/api/admin/pos/terminals')
            ->assertOk()->json('data');
        $this->assertCount(1, $rows);

        // Tenant owners have no pos_fleet.view: 403 at the admin boundary.
        $this->actingAs($this->owner)->getJson('/api/admin/pos/terminals')->assertForbidden();
    }

    public function test_dashboard_terminal_list_is_tenant_scoped(): void
    {
        ['terminal' => $terminal] = $this->claimTerminal();

        $other = Restaurant::factory()->create();
        $other->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $otherOwner = User::factory()->restaurantAdmin($other->id)->create();

        // The neighbour sees nothing, and acting on the foreign id is a 404 —
        // invisible, not forbidden.
        $this->assertSame([], $this->actingAs($otherOwner)->getJson('/api/dashboard/pos/terminals')->json('data'));
        $this->actingAs($otherOwner)->deleteJson("/api/dashboard/pos/terminals/{$terminal->id}")->assertNotFound();
    }

    public function test_an_active_terminal_cannot_be_deleted(): void
    {
        ['terminal' => $terminal] = $this->claimTerminal();

        $this->actingAs($this->owner)
            ->deleteJson("/api/dashboard/pos/terminals/{$terminal->id}")
            ->assertStatus(422)
            ->assertJsonPath('code', 'TERMINAL_STILL_ACTIVE');
    }

    public function test_a_revoked_never_used_terminal_can_be_deleted(): void
    {
        ['terminal' => $terminal] = $this->claimTerminal();

        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$terminal->id}/revoke")->assertOk();
        $this->actingAs($this->owner)
            ->deleteJson("/api/dashboard/pos/terminals/{$terminal->id}")->assertOk();

        $this->assertDatabaseMissing('pos_terminals', ['id' => $terminal->id]);
    }

    public function test_a_terminal_with_shift_history_is_kept(): void
    {
        ['terminal' => $terminal] = $this->claimTerminal();

        // The record anchors money history: pos_shifts cascade on terminal
        // delete, so a till that ever ran a shift must refuse cleanup. The
        // shift has to have TRADED — a float in the drawer is enough.
        DB::table('pos_shifts')->insert([
            'restaurant_id' => $this->restaurant->id,
            'branch_id' => $this->branch->id,
            'pos_terminal_id' => $terminal->id,
            'client_transaction_id' => (string) Str::uuid(),
            'opened_at' => now(),
            'received_at' => now(),
            'opening_float_minor' => 20000,
            'closed_at' => now(),
            'counted_cash_minor' => 20000,
            'status' => 'closed',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$terminal->id}/revoke")->assertOk();
        $this->actingAs($this->owner)
            ->deleteJson("/api/dashboard/pos/terminals/{$terminal->id}")
            ->assertStatus(422)
            ->assertJsonPath('code', 'TERMINAL_HAS_HISTORY');

        $this->assertDatabaseHas('pos_terminals', ['id' => $terminal->id]);
    }

    /**
     * The leftover this rule exists to remove. Pairing a till for a test and
     * opening a shift on it moves no money, and an empty shift row used to pin
     * the terminal forever — the dashboard could neither delete it nor explain
     * why, because "recorded sales or shifts" was true of a drawer that had
     * never been opened.
     */
    public function test_a_terminal_whose_only_shift_never_traded_is_deleted(): void
    {
        ['terminal' => $terminal] = $this->claimTerminal();

        $shift = DB::table('pos_shifts')->insertGetId([
            'restaurant_id' => $this->restaurant->id,
            'branch_id' => $this->branch->id,
            'pos_terminal_id' => $terminal->id,
            'client_transaction_id' => (string) Str::uuid(),
            'opened_at' => now(),
            'received_at' => now(),
            'opening_float_minor' => 0,
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$terminal->id}/revoke")->assertOk();
        $this->actingAs($this->owner)
            ->deleteJson("/api/dashboard/pos/terminals/{$terminal->id}")->assertOk();

        $this->assertDatabaseMissing('pos_terminals', ['id' => $terminal->id]);
        // It cascades with the row it belonged to rather than being orphaned.
        $this->assertDatabaseMissing('pos_shifts', ['id' => $shift]);
    }

    // ------------------------------------- XORD-042: list says what delete will do

    /** A provisioned terminal through the dashboard, the way an owner makes one. */
    private function provisionTerminal(string $name): int
    {
        return $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => $name, 'branch_id' => $this->branch->id])
            ->assertCreated()
            ->json('data.id');
    }

    private function shiftOn(int $terminalId, array $columns): void
    {
        DB::table('pos_shifts')->insert(array_merge([
            'restaurant_id' => $this->restaurant->id,
            'branch_id' => $this->branch->id,
            'pos_terminal_id' => $terminalId,
            'client_transaction_id' => (string) Str::uuid(),
            'opened_at' => now(),
            'received_at' => now(),
            'opening_float_minor' => 0,
            'status' => 'open',
            'created_at' => now(),
            'updated_at' => now(),
        ], $columns));
    }

    /** @return array<string,bool|null> terminal name => has_money_history */
    private function historyFlags(): array
    {
        return collect($this->actingAs($this->owner)->getJson('/api/dashboard/pos/terminals')
            ->assertOk()->json('data'))
            ->mapWithKeys(fn ($t) => [$t['name'] => $t['has_money_history'] ?? null])
            ->all();
    }

    /**
     * The flag is the delete rule read in advance: an order, or a shift that
     * moved money (float, count or close), and nothing else — an empty open
     * shift is the test-pairing leftover delete() removes.
     */
    public function test_the_terminal_list_says_which_terminals_have_money_history(): void
    {
        $this->provisionTerminal('Unused');
        $this->shiftOn($this->provisionTerminal('Empty shift'), []);
        $this->shiftOn($this->provisionTerminal('Float'), ['opening_float_minor' => 5000]);
        $this->shiftOn($this->provisionTerminal('Closed'), ['closed_at' => now(), 'status' => 'closed']);
        $this->shiftOn($this->provisionTerminal('Counted'), ['counted_cash_minor' => 0]);
        DB::table('orders')->insert([
            'restaurant_id' => $this->restaurant->id,
            'pos_terminal_id' => $this->provisionTerminal('Sold'),
            'items' => '[]',
            'created_at' => now(),
            'updated_at' => now(),
        ]);

        $this->assertSame([
            'Sold' => true,
            'Counted' => true,
            'Closed' => true,
            'Float' => true,
            'Empty shift' => false,
            'Unused' => false,
        ], $this->historyFlags());
    }

    /** The page decides from the flag, so the flag must agree with delete(). */
    public function test_the_flag_agrees_with_what_delete_answers(): void
    {
        $kept = $this->provisionTerminal('Kept');
        $this->shiftOn($kept, ['opening_float_minor' => 5000]);
        $gone = $this->provisionTerminal('Gone');
        $this->shiftOn($gone, []);

        foreach ([$kept, $gone] as $id) {
            $this->actingAs($this->owner)->postJson("/api/dashboard/pos/terminals/{$id}/revoke")->assertOk();
        }
        $this->assertSame(['Gone' => false, 'Kept' => true], $this->historyFlags());

        $this->actingAs($this->owner)->deleteJson("/api/dashboard/pos/terminals/{$kept}")
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_HAS_HISTORY');
        $this->actingAs($this->owner)->deleteJson("/api/dashboard/pos/terminals/{$gone}")->assertOk();
    }

    /** One query for the whole page, not one per terminal. */
    public function test_the_flag_costs_the_same_queries_for_one_terminal_or_many(): void
    {
        $count = function (): int {
            $n = 0;
            DB::listen(function () use (&$n) {
                $n++;
            });
            $this->actingAs($this->owner)->getJson('/api/dashboard/pos/terminals')->assertOk();

            return $n;
        };

        $this->shiftOn($this->provisionTerminal('One'), ['opening_float_minor' => 5000]);
        $one = $count();
        foreach (['Two', 'Three', 'Four'] as $name) {
            $this->shiftOn($this->provisionTerminal($name), ['opening_float_minor' => 5000]);
        }

        $this->assertSame($one, $count());
    }

    /** Responses that do not compute it keep their shape. */
    public function test_provisioning_response_does_not_carry_the_flag(): void
    {
        $data = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'New', 'branch_id' => $this->branch->id])
            ->assertCreated()->json('data');

        $this->assertArrayNotHasKey('has_money_history', $data);
    }

    // --------------------------------------------------- seat enforcement

    /** Give the tenant a plan that buys exactly $seats terminals. */
    private function planWithSeats(int $seats): Plan
    {
        $plan = Plan::create(['name' => 'Seats'.$seats, 'max_terminals' => $seats]);
        $this->restaurant->forceFill(['subscription_plan' => $plan->name])->save();

        return $plan;
    }

    /**
     * Owner decision, 2026-09-05: the plan caps terminal ROWS, not just paired
     * devices. A two-seat plan holds two terminals, so the limit is met in the
     * dashboard by the person who can upgrade — never at the counter by
     * whoever is holding a device that will not pair.
     */
    public function test_creating_a_terminal_is_refused_when_every_seat_is_spent(): void
    {
        $this->planWithSeats(1);
        $this->claimTerminal(); // spends the only seat

        $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 2', 'branch_id' => $this->branch->id])
            ->assertStatus(422)
            ->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT')
            ->assertJsonPath('details.seats.max', 1);

        // Refused means nothing was written — no half-built row squatting the
        // fleet list, the same posture a refused Path B register has.
        $this->assertSame(1, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_an_unclaimed_terminal_still_spends_its_seat(): void
    {
        // The hole this closes: on a two-seat plan, provisioning two rows that
        // nobody has paired yet must exhaust the plan. Counting only paired
        // devices would let a client build a fleet list of any size and meet
        // the limit one device at a time.
        $this->planWithSeats(2);

        foreach (['Till 1', 'Till 2'] as $name) {
            $this->actingAs($this->owner)
                ->postJson('/api/dashboard/pos/terminals', ['name' => $name, 'branch_id' => $this->branch->id])
                ->assertCreated();
        }

        $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 3', 'branch_id' => $this->branch->id])
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT');

        $this->assertSame(2, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_the_super_admin_route_is_capped_by_the_same_count(): void
    {
        // Both front doors go through one service, so the platform side cannot
        // be a way around a limit the tenant's own dashboard enforces.
        $this->planWithSeats(1);
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$this->restaurant->id}/terminals",
                ['name' => 'Till 1', 'branch_id' => $this->branch->id])
            ->assertCreated();

        $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$this->restaurant->id}/terminals",
                ['name' => 'Till 2', 'branch_id' => $this->branch->id])
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT');
    }

    public function test_revoking_frees_a_seat_immediately(): void
    {
        $this->planWithSeats(1);
        ['terminal' => $first] = $this->claimTerminal();

        // Full house: the second till cannot even be created now.
        $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 2', 'branch_id' => $this->branch->id])
            ->assertStatus(422);

        $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$first->id}/revoke")->assertOk();

        // Seat freed: create, pair, done — no waiting, no second plan change.
        $second = $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'Till 2', 'branch_id' => $this->branch->id])
            ->assertCreated()->json('data');
        $code = $this->actingAs($this->owner)
            ->postJson("/api/dashboard/pos/terminals/{$second['id']}/pairing-code")
            ->json('pairing_code');

        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug, 'pairing_code' => $code,
            'fingerprint' => 'sha256:second',
        ])->assertOk();
    }

    public function test_a_licence_seat_count_overrides_the_plan_at_creation(): void
    {
        // A bespoke deal is not a plan tier: the licence is the record of what
        // was actually sold, so it wins in both directions.
        $this->planWithSeats(1);
        app(LicenceIssuer::class)->issue($this->restaurant, [
            'issued_at' => now()->subDay(), 'expires_at' => now()->addYear(),
            'max_terminals' => 3, 'modes' => ['cloud'],
        ]);

        foreach (['A', 'B', 'C'] as $name) {
            $this->actingAs($this->owner)
                ->postJson('/api/dashboard/pos/terminals', ['name' => $name, 'branch_id' => $this->branch->id])
                ->assertCreated();
        }

        $this->actingAs($this->owner)
            ->postJson('/api/dashboard/pos/terminals', ['name' => 'D', 'branch_id' => $this->branch->id])
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT');
    }

    public function test_an_uncapped_tenant_can_still_create_terminals(): void
    {
        // No plan, no licence: nothing bought a limit, so nothing enforces one.
        // A tenant must never be locked out by an absent number.
        $this->restaurant->forceFill(['subscription_plan' => null])->save();

        foreach (range(1, 5) as $i) {
            $this->actingAs($this->owner)
                ->postJson('/api/dashboard/pos/terminals', ['name' => "Till {$i}", 'branch_id' => $this->branch->id])
                ->assertCreated();
        }
    }

    public function test_a_till_already_trading_is_never_cut_off_by_a_full_house(): void
    {
        $plan = $this->planWithSeats(1);
        ['token' => $token] = $this->claimTerminal();

        // The plan shrinks to zero seats under a till that is already working.
        // Everything it does mid-service must keep working: the "never brick a
        // till" rule protects trade in progress, and only claims are gated.
        $plan->forceFill(['max_terminals' => 0])->save();

        $this->getJson('/api/pos/bootstrap', $this->deviceHeaders($token))->assertOk();
        $this->postJson('/api/pos/terminals/heartbeat', ['pending_count' => 0],
            $this->deviceHeaders($token))->assertOk();
    }

    public function test_a_replayed_claim_does_not_need_a_second_seat(): void
    {
        $this->planWithSeats(1);
        ['token' => $token, 'pairing_code' => $code] = $this->claimTerminal();

        // The same device retrying after a timeout is re-claiming its OWN
        // seat; counting it again would refuse a till that already paid for
        // one and leave it unable to finish setting up.
        $replay = $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $this->restaurant->slug,
            'pairing_code' => $code,
            'platform' => 'windows',
            'app_version' => '1.4.2',
            'fingerprint' => 'sha256:test-device',
        ])->assertOk()->json();

        $this->assertSame($token, $replay['device_token']);
    }

    public function test_an_uncapped_plan_still_admits_terminals(): void
    {
        // No plan, no licence: nothing bought a seat limit, so nothing enforces
        // one. A tenant must not be locked out by an absent number.
        $this->restaurant->forceFill(['subscription_plan' => null])->save();
        $this->claimTerminal();
        $this->assertSame(1, PosTerminal::withoutGlobalScopes()->count());
    }
}

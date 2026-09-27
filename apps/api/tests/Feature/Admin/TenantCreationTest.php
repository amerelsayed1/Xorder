<?php

namespace Tests\Feature\Admin;

use App\Models\Branch;
use App\Models\Plan;
use App\Models\PosLicence;
use App\Models\PosShift;
use App\Models\PosTerminal;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

/**
 * Tenant creation = tenant + licence, and NOTHING else (owner decision,
 * 2026-09-05).
 *
 * The two halves of that sentence are both load-bearing and both tested here.
 * The licence must exist, or a client is sold something it cannot install. And
 * NO terminal may exist — not a default one, not a primary one, not a
 * placeholder — because a terminal that appears on its own occupies a licensed
 * seat nobody asked for and shows up in the fleet as a till that will never
 * check in. Zero terminals is the correct outcome, and the tenant page has to
 * render it as an ordinary empty state rather than a failure.
 *
 * Terminals come afterwards, one deliberate Super Admin action at a time.
 */
class TenantCreationTest extends TestCase
{
    use RefreshDatabase;

    private function superAdmin(): User
    {
        return User::factory()->superAdmin()->create();
    }

    /** @return array<string,mixed> */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name_en' => 'Tasty',
            'slug' => 'tasty',
            'default_language' => 'en',
            'currency' => 'EGP',
            'admin' => ['name' => 'Owner', 'username' => 'owner', 'email' => 'owner@tasty.com'],
        ], $overrides);
    }

    // ---------------------------------------------------------------- create

    public function test_creating_a_tenant_creates_its_licence_and_no_terminal(): void
    {
        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload())
            ->assertCreated()
            ->assertJsonPath('data.slug', 'tasty')
            // The activation key is returned exactly once — the row keeps only
            // its HMAC — so the response is the operator's only chance to copy
            // it. If this key disappears from the payload, a freshly created
            // client can never activate online.
            ->assertJsonStructure(['generated_password', 'activation_key', 'licence', 'licence_file']);

        $restaurant = Restaurant::where('slug', 'tasty')->firstOrFail();

        $licence = PosLicence::where('restaurant_id', $restaurant->id)->first();
        $this->assertNotNull($licence, 'a tenant must be born with a licence');
        $this->assertNotSame('', $licence->signature, 'the licence must be signed at issuance');

        $this->assertSame(
            0,
            PosTerminal::withoutGlobalScopes()->where('restaurant_id', $restaurant->id)->count(),
            'tenant creation must not create a terminal of any kind',
        );
    }

    public function test_the_licence_term_follows_the_subscription_dates(): void
    {
        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload([
                'subscription_start_date' => '2026-01-01',
                'subscription_end_date' => '2026-12-31',
            ]))->assertCreated();

        $licence = PosLicence::firstOrFail();

        $this->assertSame('2026-01-01', $licence->issued_at->toDateString());
        $this->assertSame('2026-12-31', $licence->expires_at->toDateString());
    }

    public function test_licence_seats_follow_the_plan_but_provision_nothing(): void
    {
        Plan::create([
            'name' => 'Growth', 'price' => 900, 'currency' => 'EGP',
            'feature_keys' => ['qr_menu', 'pos'], 'max_terminals' => 5, 'is_active' => true,
        ]);

        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload(['subscription_plan' => 'Growth']))
            ->assertCreated();

        $licence = PosLicence::firstOrFail();

        // Five seats SOLD, zero tills created. The distinction is the whole
        // point of the split: max_terminals is a ceiling, never an instruction.
        $this->assertSame(5, $licence->max_terminals);
        $this->assertSame(0, PosTerminal::withoutGlobalScopes()->count());
        $this->assertContains('pos', $licence->features);
    }

    public function test_explicit_licence_overrides_win_over_the_plan(): void
    {
        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload([
                'licence' => [
                    'max_terminals' => 12,
                    'modes' => ['cloud', 'offline'],
                    'grace_days' => 30,
                    'notes' => 'Bespoke: 12 tills, two sites.',
                ],
            ]))->assertCreated();

        $licence = PosLicence::firstOrFail();

        $this->assertSame(12, $licence->max_terminals);
        $this->assertSame(30, $licence->grace_days);
        $this->assertSame(['cloud', 'offline'], $licence->modes);
        $this->assertSame(0, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_a_licence_end_date_alone_is_enough(): void
    {
        // `expires_at` is validated `after:licence.issued_at`, and issued_at is
        // optional — a comparison rule against a field the caller omitted must
        // not reject the request, or "sell them a year from today" becomes
        // impossible without restating today's date.
        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload([
                'licence' => ['expires_at' => '2028-01-01'],
            ]))->assertCreated();

        $this->assertSame('2028-01-01', PosLicence::firstOrFail()->expires_at->toDateString());
    }

    public function test_the_creation_form_refuses_an_empty_modes_list(): void
    {
        // An empty modes[] signs a licence in which every deployment mode
        // fails, which the till reports as modeNotLicensed — a bricked terminal
        // as far as anyone at the counter can tell.
        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload(['licence' => ['modes' => []]]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('licence.modes');
    }

    // ------------------------------------------------------- transactionality

    public function test_a_licence_failure_rolls_the_whole_tenant_back(): void
    {
        // No signing key = LicenceIssuer throws. The tenant, its admin, its
        // roles and its branch must all go with it: a client that exists but
        // can never be licensed is the exact partial state this transaction
        // exists to prevent.
        config(['licence.signing_key' => '']);

        $this->actingAs($this->superAdmin())
            ->postJson('/api/admin/restaurants', $this->payload([
                'branch' => ['name_en' => 'Maadi', 'code' => 'MAADI'],
            ]));

        $this->assertDatabaseMissing('restaurants', ['slug' => 'tasty']);
        $this->assertDatabaseMissing('users', ['username' => 'owner']);
        $this->assertSame(0, PosLicence::count());
        $this->assertSame(0, Branch::withoutGlobalScopes()->count());
    }

    // ------------------------------------------------- manual terminal creation

    public function test_super_admin_creates_a_terminal_for_an_existing_tenant(): void
    {
        [$restaurant, $branch] = $this->tenantWithBranch();

        $terminal = $this->actingAs($this->superAdmin())
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                'name' => 'Front Till',
                'branch_id' => $branch->id,
            ])->assertCreated()->json('data');

        $row = PosTerminal::withoutGlobalScopes()->findOrFail($terminal['id']);

        $this->assertSame($restaurant->id, $row->restaurant_id);
        $this->assertSame($branch->id, $row->branch_id);
        // Created, not claimed: no device has paired with it yet, so it holds
        // no seat and carries no device token.
        $this->assertSame(PosTerminal::STATE_PROVISIONED, $row->state);
        $this->assertNull($row->device_token_hash);
    }

    public function test_several_terminals_all_belong_to_the_same_tenant(): void
    {
        [$restaurant, $branch] = $this->tenantWithBranch();
        $sa = $this->superAdmin();

        foreach (['Till 1', 'Till 2', 'Till 3'] as $name) {
            $this->actingAs($sa)
                ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                    'name' => $name, 'branch_id' => $branch->id,
                ])->assertCreated();
        }

        $terminals = PosTerminal::withoutGlobalScopes()->get();

        $this->assertCount(3, $terminals);
        $this->assertSame([$restaurant->id], $terminals->pluck('restaurant_id')->unique()->all());
        // Three rows, three distinct terminal ids — no idempotent collapse.
        $this->assertCount(3, $terminals->pluck('terminal_id')->unique());

        $this->assertCount(3, $this->actingAs($sa)
            ->getJson("/api/admin/restaurants/{$restaurant->id}/terminals")
            ->assertOk()->json('data'));
    }

    public function test_a_freshly_created_tenant_lists_zero_terminals_without_error(): void
    {
        $sa = $this->superAdmin();

        $id = $this->actingAs($sa)->postJson('/api/admin/restaurants', $this->payload())
            ->assertCreated()->json('data.id');

        // The tenant page asks for the fleet immediately after creation. An
        // empty list is an ordinary 200 with [], never a 404 or an error the
        // UI would render as a broken tenant.
        $this->actingAs($sa)->getJson("/api/admin/restaurants/{$id}/terminals")
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_a_terminal_cannot_be_created_on_another_tenants_branch(): void
    {
        [$restaurant] = $this->tenantWithBranch();
        [, $foreignBranch] = $this->tenantWithBranch('rival');

        // 404, not 403: a foreign branch id must not confirm it exists.
        $this->actingAs($this->superAdmin())
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                'name' => 'Smuggled', 'branch_id' => $foreignBranch->id,
            ])->assertNotFound();

        $this->assertSame(0, PosTerminal::withoutGlobalScopes()->count());
    }

    public function test_a_restaurant_admin_cannot_create_terminals_from_the_admin_api(): void
    {
        [$restaurant, $branch] = $this->tenantWithBranch();
        $owner = User::factory()->restaurantAdmin($restaurant->id)->create();

        $this->actingAs($owner)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                'name' => 'Till 1', 'branch_id' => $branch->id,
            ])->assertForbidden();
    }

    public function test_a_platform_created_terminal_can_be_paired_by_a_till(): void
    {
        [$restaurant, $branch] = $this->tenantWithBranch();
        $restaurant->features()->create(['feature_key' => 'pos', 'is_enabled' => true]);
        $sa = $this->superAdmin();

        $terminal = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                'name' => 'Front Till', 'branch_id' => $branch->id,
            ])->assertCreated()->json('data');

        $code = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}/pairing-code")
            ->assertOk()->json('pairing_code');

        // The claim is unauthenticated — a fresh machine has no login — and is
        // what turns "the Super Admin created a terminal" into a working till.
        $this->postJson('/api/pos/terminals/claim', [
            'tenant_slug' => $restaurant->slug,
            'pairing_code' => $code,
            'platform' => 'windows',
            'fingerprint' => 'sha256:test-device',
        ])->assertOk()->assertJsonPath('terminal.id', $terminal['terminal_id']);

        $row = PosTerminal::withoutGlobalScopes()->findOrFail($terminal['id']);
        $this->assertSame(PosTerminal::STATE_ACTIVE, $row->state);
        $this->assertSame($restaurant->id, $row->restaurant_id);
    }

    // ------------------------------------------------- revoke + delete a terminal

    public function test_a_terminal_must_be_revoked_before_it_can_be_deleted(): void
    {
        [$restaurant, $branch] = $this->tenantWithBranch();
        $sa = $this->superAdmin();

        $terminal = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals",
                ['name' => 'Till 1', 'branch_id' => $branch->id])
            ->assertCreated()->json('data');

        // Straight to delete: refused. An active terminal holds a live device
        // token, and deleting the row would strand a till holding a credential
        // the server no longer knows.
        $this->actingAs($sa)
            ->deleteJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}")
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_STILL_ACTIVE');

        $this->assertDatabaseHas('pos_terminals', ['id' => $terminal['id']]);

        $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}/revoke")
            ->assertOk();

        $this->actingAs($sa)
            ->deleteJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}")
            ->assertOk();

        $this->assertDatabaseMissing('pos_terminals', ['id' => $terminal['id']]);
    }

    public function test_deleting_frees_the_seat_it_was_holding(): void
    {
        // The reason this action exists on a capped plan: a terminal created by
        // mistake must be removable, not just parked.
        [$restaurant, $branch] = $this->tenantWithBranch();
        $plan = Plan::create(['name' => 'OneSeat', 'max_terminals' => 1, 'is_active' => true]);
        $restaurant->forceFill(['subscription_plan' => $plan->name])->save();
        $sa = $this->superAdmin();

        $create = fn (string $name) => $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals",
                ['name' => $name, 'branch_id' => $branch->id]);

        $first = $create('Mistake')->assertCreated()->json('data');
        $create('Second')->assertStatus(422)->assertJsonPath('code', 'TERMINAL_SEAT_LIMIT');

        $this->actingAs($sa)->postJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$first['id']}/revoke")->assertOk();
        $this->actingAs($sa)->deleteJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$first['id']}")->assertOk();

        $create('Second')->assertCreated();
    }

    public function test_a_terminal_that_ever_traded_is_never_deleted(): void
    {
        // Money history anchors the record. pos_shifts cascade on delete and
        // orders lose their attribution, so a till that traded stays.
        [$restaurant, $branch] = $this->tenantWithBranch();
        $sa = $this->superAdmin();

        $terminal = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals",
                ['name' => 'Traded', 'branch_id' => $branch->id])
            ->assertCreated()->json('data');

        $row = PosTerminal::withoutGlobalScopes()->findOrFail($terminal['id']);
        $shift = new PosShift;
        $shift->forceFill([
            'opened_at' => now(),
            'restaurant_id' => $restaurant->id,
            'branch_id' => $branch->id,
            'pos_terminal_id' => $row->id,
            'client_transaction_id' => (string) Str::uuid(),
            'status' => 'open',
            'opening_float_minor' => 20000,
        ])->save();

        $this->actingAs($sa)->postJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}/revoke")->assertOk();

        $this->actingAs($sa)
            ->deleteJson("/api/admin/restaurants/{$restaurant->id}/terminals/{$terminal['id']}")
            ->assertStatus(422)->assertJsonPath('code', 'TERMINAL_HAS_HISTORY');

        $this->assertDatabaseHas('pos_terminals', ['id' => $terminal['id']]);
    }

    public function test_a_terminal_of_another_tenant_cannot_be_deleted_through_this_tenant(): void
    {
        [$mine] = $this->tenantWithBranch('mine');
        [$theirs, $theirBranch] = $this->tenantWithBranch('theirs');
        $sa = $this->superAdmin();

        $foreign = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$theirs->id}/terminals",
                ['name' => 'Theirs', 'branch_id' => $theirBranch->id])
            ->assertCreated()->json('data');

        $this->actingAs($sa)->postJson("/api/admin/restaurants/{$theirs->id}/terminals/{$foreign['id']}/revoke")->assertOk();

        // 404, not 403 — the same no-existence-leak posture as a foreign branch.
        $this->actingAs($sa)
            ->deleteJson("/api/admin/restaurants/{$mine->id}/terminals/{$foreign['id']}")
            ->assertNotFound();

        $this->assertDatabaseHas('pos_terminals', ['id' => $foreign['id']]);
    }

    // -------------------------------------------------------- pre-existing data

    public function test_existing_tenants_and_their_terminals_are_untouched(): void
    {
        // A tenant that predates the split: terminals already provisioned, and
        // in the general case no licence row at all. Neither is migrated and
        // neither stops working — the change applies to NEW tenant creation.
        [$restaurant, $branch] = $this->tenantWithBranch('legacy');
        $sa = $this->superAdmin();

        $existing = $this->actingAs($sa)
            ->postJson("/api/admin/restaurants/{$restaurant->id}/terminals", [
                'name' => 'Legacy Till', 'branch_id' => $branch->id,
            ])->assertCreated()->json('data');

        // Creating a brand-new tenant afterwards must not disturb it.
        $this->actingAs($sa)->postJson('/api/admin/restaurants', $this->payload())->assertCreated();

        $this->assertDatabaseHas('pos_terminals', [
            'id' => $existing['id'],
            'terminal_id' => $existing['terminal_id'],
            'restaurant_id' => $restaurant->id,
        ]);

        $this->assertCount(1, $this->actingAs($sa)
            ->getJson("/api/admin/restaurants/{$restaurant->id}/terminals")
            ->assertOk()->json('data'));
    }

    /** @return array{0: Restaurant, 1: Branch} */
    private function tenantWithBranch(string $slug = 'existing'): array
    {
        $restaurant = Restaurant::factory()->create(['slug' => $slug, 'currency' => 'EGP']);

        $branch = new Branch(['name_en' => 'Main', 'code' => strtoupper($slug)]);
        $branch->restaurant_id = $restaurant->id;
        $branch->save();

        return [$restaurant, $branch];
    }
}

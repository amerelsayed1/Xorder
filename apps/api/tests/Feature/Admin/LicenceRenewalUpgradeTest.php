<?php

namespace Tests\Feature\Admin;

use App\Models\Plan;
use App\Models\PosLicence;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\File;
use Illuminate\Support\Facades\Log;
use Tests\TestCase;

/**
 * XORD-009 — renewal is how a licence is edited and upgraded.
 *
 * The signed artifact is the record of what the customer was sold, so nothing
 * is changed in place: a renewal signs the new terms on a new row and keeps the
 * old one. These tests pin that every field the licence's kind lets an operator
 * choose can be changed there — and that the client, the kind and the old row
 * cannot.
 */
class LicenceRenewalUpgradeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        $pair = sodium_crypto_sign_keypair();
        config([
            'licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair)),
            'licence.key_id' => 'v1',
        ]);
    }

    private function admin(): User
    {
        return User::factory()->superAdmin()->create();
    }

    private function decode(string $b64url): string
    {
        return base64_decode(strtr($b64url, '-_', '+/').str_repeat('=', (4 - strlen($b64url) % 4) % 4));
    }

    /** @return array<string,mixed> */
    private function claimsOf(array $body): array
    {
        return json_decode($this->decode($body['file']['payload']), true);
    }

    private function cloud(array $overrides = []): array
    {
        $restaurant = Restaurant::factory()->create(['slug' => 'demo']);

        return $this->actingAs($this->admin())->postJson('/api/admin/pos/licences', array_merge([
            'restaurant_id' => $restaurant->id,
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 2,
            'modes' => ['cloud'],
            'features' => ['qr_menu'],
        ], $overrides))->assertCreated()->json();
    }

    private function offline(array $overrides = []): array
    {
        return $this->actingAs($this->admin())->postJson('/api/admin/pos/licences/offline', array_merge([
            'customer_name' => 'Al Asima Grill',
            'customer_slug' => 'al-asima',
            'contact_name' => 'Rana Fahmy',
            'contact_email' => 'rana@al-asima.example',
            'contact_phone' => '+201000000000',
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 3,
            'max_users' => 8,
            'max_offline_days' => 30,
            'notes' => 'Paid in full.',
        ], $overrides))->assertCreated()->json();
    }

    private function renew(array $licence, array $body)
    {
        return $this->actingAs($this->admin())->postJson(
            "/api/admin/pos/licences/{$licence['data']['id']}/renew",
            array_merge(['issued_at' => '2027-09-01', 'expires_at' => '2028-09-01'], $body),
        );
    }

    // ----------------------------------------------------------- cloud licence

    public function test_a_cloud_renewal_upgrades_plan_features_modes_and_capacity(): void
    {
        $plan = Plan::create(['name' => 'Pro']);
        $old = $this->cloud();

        $renewal = $this->renew($old, [
            'plan_id' => $plan->id,
            'max_terminals' => 6,
            'max_users' => 20,
            'grace_days' => 30,
            'warn_days' => 45,
            'max_offline_days' => 14,
            'features' => ['qr_menu', 'dine_in', 'delivery', 'pos'],
            'modes' => ['cloud', 'offline'],
        ])->assertCreated()->json();

        $claims = $this->claimsOf($renewal);
        $this->assertSame(6, $claims['max_terminals']);
        $this->assertSame(20, $claims['max_users']);
        $this->assertSame(30, $claims['grace_days']);
        $this->assertSame(45, $claims['warn_days']);
        $this->assertSame(14, $claims['max_offline_days']);
        $this->assertEqualsCanonicalizing(['qr_menu', 'dine_in', 'delivery', 'pos'], $claims['features']);
        $this->assertEqualsCanonicalizing(['cloud', 'offline'], $claims['modes']);
        $this->assertSame($plan->id, $renewal['data']['plan']['id']);
    }

    public function test_the_old_row_is_kept_and_superseded_not_edited(): void
    {
        $old = $this->cloud();
        $renewal = $this->renew($old, ['max_terminals' => 9])->assertCreated()->json();

        $before = PosLicence::findOrFail($old['data']['id']);
        $this->assertSame(2, $before->max_terminals, 'what they were sold in 2026 is still on record');
        $this->assertSame($renewal['data']['id'], $before->superseded_by_id);
    }

    public function test_a_renewal_cannot_move_the_licence_to_another_client_or_change_its_kind(): void
    {
        $old = $this->cloud();
        $other = Restaurant::factory()->create(['slug' => 'other']);

        $renewal = $this->renew($old, [
            'restaurant_id' => $other->id,
            'kind' => 'offline',
            'customer_slug' => 'hijack',
        ])->assertCreated()->json();

        $this->assertSame('cloud', $renewal['data']['kind']);
        $this->assertSame($old['data']['restaurant']['id'], $renewal['data']['restaurant']['id']);
        $this->assertNull($renewal['data']['customer_slug']);
    }

    public function test_a_plan_that_does_not_exist_is_refused(): void
    {
        $this->renew($this->cloud(), ['plan_id' => 99999])
            ->assertUnprocessable()->assertJsonValidationErrors('plan_id');
    }

    public function test_a_licence_with_no_mode_is_refused(): void
    {
        $this->renew($this->cloud(), ['modes' => []])
            ->assertUnprocessable()->assertJsonValidationErrors('modes');
    }

    // --------------------------------------------------------- offline licence

    public function test_an_offline_renewal_upgrades_capacity_and_the_term(): void
    {
        $renewal = $this->renew($this->offline(), [
            'max_terminals' => 10,
            'max_users' => 30,
            'max_offline_days' => 60,
            'grace_days' => 7,
        ])->assertCreated()->json();

        $claims = $this->claimsOf($renewal);
        $this->assertSame(10, $claims['max_terminals']);
        $this->assertSame(30, $claims['max_users']);
        $this->assertSame(60, $claims['max_offline_days']);
        $this->assertSame(7, $claims['grace_days']);
    }

    public function test_an_offline_renewal_can_move_to_unlimited_users_and_never_check_in(): void
    {
        $renewal = $this->renew($this->offline(), ['max_users' => null, 'max_offline_days' => null])
            ->assertCreated()->json();

        $claims = $this->claimsOf($renewal);
        $this->assertNull($claims['max_users'], 'a key present and null clears it');
        $this->assertNull($claims['max_offline_days']);
    }

    public function test_leaving_a_field_out_keeps_it(): void
    {
        $renewal = $this->renew($this->offline(), [])->assertCreated()->json();

        $claims = $this->claimsOf($renewal);
        $this->assertSame(8, $claims['max_users']);
        $this->assertSame(30, $claims['max_offline_days']);
        $this->assertSame(3, $claims['max_terminals']);
    }

    public function test_an_offline_renewal_can_sell_the_licence_outright(): void
    {
        $renewal = $this->renew($this->offline(), ['lifetime' => true, 'expires_at' => null])
            ->assertCreated()->json();

        $this->assertTrue($renewal['data']['lifetime']);
        $this->assertNull($renewal['data']['expires_at']);
    }

    public function test_the_business_name_may_be_corrected_but_not_the_identifier(): void
    {
        $renewal = $this->renew($this->offline(), [
            'customer_name' => 'Al Asima Grill & Cafe',
            'customer_slug' => 'something-else',
        ])->assertCreated()->json();

        $this->assertSame('Al Asima Grill & Cafe', $renewal['data']['customer_name']);
        $this->assertSame('al-asima', $renewal['data']['customer_slug']);
        $this->assertSame('Al Asima Grill & Cafe', $this->claimsOf($renewal)['tenant_name']);
        $this->assertSame('al-asima', $this->claimsOf($renewal)['tenant_slug']);
    }

    public function test_an_offline_renewal_cannot_pick_features_modes_or_a_plan(): void
    {
        $old = $this->offline();
        $oldClaims = $this->claimsOf($old);

        $renewal = $this->renew($old, [
            'features' => ['pos'],
            'modes' => ['cloud'],
            'plan_id' => Plan::create(['name' => 'Pro'])->id,
            'branch_ids' => [1, 2],
        ])->assertCreated()->json();

        $claims = $this->claimsOf($renewal);
        $this->assertSame($oldClaims['features'], $claims['features'], 'the whole product, always');
        $this->assertSame(['offline'], $claims['modes']);
        $this->assertNull($renewal['data']['plan']);
    }

    public function test_contact_details_and_notes_can_be_changed_or_cleared(): void
    {
        $renewal = $this->renew($this->offline(), [
            'contact_name' => 'Omar Said',
            'contact_phone' => null,
            'notes' => null,
        ])->assertCreated()->json();

        $this->assertSame('Omar Said', $renewal['data']['contact_name']);
        $this->assertNull($renewal['data']['contact_phone']);
        $this->assertNull($renewal['data']['notes']);
        $this->assertSame('rana@al-asima.example', $renewal['data']['contact_email'], 'left out: kept');
    }

    // ------------------------------------------------------------- device binding

    public function test_device_fingerprints_are_kept_unless_the_renewal_changes_them(): void
    {
        $old = $this->offline(['fingerprints' => ['fp-aaa', 'fp-bbb']]);

        $kept = $this->renew($old, [])->assertCreated()->json();
        $this->assertEqualsCanonicalizing(['fp-aaa', 'fp-bbb'], $this->claimsOf($kept)['fingerprints']);

        // The next renewal starts from the newest row, as the screen does.
        $changed = $this->renew($kept, ['fingerprints' => ['fp-ccc']])->assertCreated()->json();
        $this->assertSame(['fp-ccc'], $this->claimsOf($changed)['fingerprints']);
    }

    // ----------------------------------------------------------------- the key

    public function test_the_activation_key_is_kept_across_an_upgrade(): void
    {
        $old = $this->cloud();
        $renewal = $this->renew($old, ['max_terminals' => 9])->assertCreated()->json();

        $this->assertTrue($renewal['key_unchanged']);
        $this->assertNull($renewal['activation_key']);
        $this->assertSame(
            PosLicence::findOrFail($old['data']['id'])->key_hash,
            PosLicence::findOrFail($renewal['data']['id'])->key_hash,
        );
    }

    // -------------------------------------------------------------------- audit

    public function test_the_audit_row_says_what_the_upgrade_changed(): void
    {
        $old = $this->offline(['fingerprints' => ['fp-aaa']]);

        // The audit sink is the per-day activity file; point it somewhere
        // disposable for this test, as the key-reveal test does.
        $dir = storage_path('framework/testing/activity-'.uniqid());
        config(['platform.activity_log_file' => true, 'logging.channels.activity.path' => $dir.'/activity.log']);
        Log::forgetChannel('activity');
        try {
            $this->renew($old, [
                'max_terminals' => 10,
                'max_users' => null,
                'contact_name' => 'Omar Said',
                'fingerprints' => ['fp-zzz'],
            ])->assertCreated();

            $file = file_get_contents($dir.'/activity-'.now()->format('Y-m-d').'.log');
            $line = collect(explode("\n", trim($file)))
                ->map(fn ($l) => json_decode($l, true))
                ->first(fn ($row) => ($row['action'] ?? null) === 'pos_licence.renewed');
            $this->assertNotNull($line, 'a pos_licence.renewed row was written');
            $properties = $line['properties'];

            $this->assertEquals(['from' => 3, 'to' => 10], $properties['changes']['max_terminals']);
            $this->assertEquals(['from' => 8, 'to' => null], $properties['changes']['max_users']);
            $this->assertArrayNotHasKey('grace_days', $properties['changes'], 'unchanged fields are not listed');

            // Personal and machine-identifying values are named, never recorded.
            $this->assertEqualsCanonicalizing(['contact_name', 'fingerprints'], $properties['changed_private']);
            $this->assertStringNotContainsString('Omar', $file);
            $this->assertStringNotContainsString('fp-zzz', $file);
        } finally {
            Log::forgetChannel('activity');
            File::deleteDirectory($dir);
        }
    }

    // -------------------------------------------------------------- permissions

    public function test_only_a_super_admin_holding_licences_manage_may_renew(): void
    {
        $old = $this->cloud();
        $owner = User::factory()->restaurantAdmin(Restaurant::factory()->create()->id)->create();

        $this->actingAs($owner)->postJson("/api/admin/pos/licences/{$old['data']['id']}/renew", [
            'issued_at' => '2027-09-01', 'expires_at' => '2028-09-01', 'max_terminals' => 99,
        ])->assertForbidden();

        $this->assertSame(2, PosLicence::findOrFail($old['data']['id'])->max_terminals);
    }

    public function test_a_revoked_licence_cannot_be_renewed_into_something_bigger(): void
    {
        $old = $this->cloud();
        $this->actingAs($this->admin())
            ->postJson("/api/admin/pos/licences/{$old['data']['id']}/revoke", ['reason' => 'test'])
            ->assertOk();

        $this->renew($old, ['max_terminals' => 50])
            ->assertUnprocessable()->assertJsonPath('code', 'LICENCE_NOT_LIVE');
        $this->assertSame(1, PosLicence::count(), 'no new licence was written');
    }

    public function test_a_licence_already_replaced_cannot_be_renewed_again(): void
    {
        $old = $this->cloud();
        $this->renew($old, ['max_terminals' => 4])->assertCreated();

        // Renewing the OLD row would fork two live licences under one key.
        $this->renew($old, ['max_terminals' => 8])
            ->assertUnprocessable()->assertJsonPath('code', 'LICENCE_NOT_LIVE');
        $this->assertSame(2, PosLicence::count());
    }

    public function test_a_renewal_that_keeps_the_key_keeps_the_first_activation_date(): void
    {
        $old = $this->offline();
        $this->postJson('/api/pos/licence/activate', ['key' => $old['activation_key'], 'fingerprint' => 'fp-1'])->assertOk();
        $first = PosLicence::findOrFail($old['data']['id'])->activated_at;
        $this->assertNotNull($first);

        $renewal = $this->renew($old, [])->assertCreated()->json();

        $this->assertSame($first->toIso8601String(), $renewal['data']['activated_at'], 'not "never installed"');
    }

    public function test_a_rotated_key_starts_with_no_activation(): void
    {
        $old = $this->offline();
        $this->postJson('/api/pos/licence/activate', ['key' => $old['activation_key'], 'fingerprint' => 'fp-1'])->assertOk();

        $renewal = $this->renew($old, ['rotate_key' => true])->assertCreated()->json();

        $this->assertNull($renewal['data']['activated_at']);
    }
}

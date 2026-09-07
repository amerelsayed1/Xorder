<?php

namespace Tests\Feature\Admin;

use App\Enums\RoleEnum;
use App\Models\PosLicence;
use App\Models\Restaurant;
use App\Models\User;
use App\Support\LicenceKey;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * POS-BE-015 — Super Admin issues licences; a till exchanges a key for the
 * signed file and verifies it entirely offline.
 *
 * The load-bearing assertions here are the ones the Flutter client depends on
 * and cannot negotiate: the exact claim keys, the exact bytes that are signed,
 * and byte-identical idempotency. If those drift, tills in the field stop
 * verifying and there is no way to tell them why.
 */
class PosLicenceTest extends TestCase
{
    use RefreshDatabase;

    private string $publicKey;

    protected function setUp(): void
    {
        parent::setUp();

        $pair = sodium_crypto_sign_keypair();
        $this->publicKey = sodium_crypto_sign_publickey($pair);

        config([
            'licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair)),
            'licence.key_id' => 'v1',
        ]);
    }

    private function restaurant(string $slug = 'demo'): Restaurant
    {
        return Restaurant::factory()->create(['slug' => $slug, 'name_en' => 'Demo Diner']);
    }

    /** @return array<string,mixed> */
    private function payload(Restaurant $restaurant, array $overrides = []): array
    {
        return array_merge([
            'restaurant_id' => $restaurant->id,
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 4,
            'modes' => ['cloud', 'branch_server'],
            'features' => ['qr_menu', 'dine_in'],
        ], $overrides);
    }

    private function issue(Restaurant $restaurant, array $overrides = []): array
    {
        $sa = User::factory()->superAdmin()->create();

        return $this->actingAs($sa)
            ->postJson('/api/admin/pos/licences', $this->payload($restaurant, $overrides))
            ->assertCreated()
            ->json();
    }

    private function decode(string $b64url): string
    {
        return base64_decode(strtr($b64url, '-_', '+/').str_repeat('=', (4 - strlen($b64url) % 4) % 4));
    }

    // ---------------------------------------------------------------- issuance

    public function test_super_admin_issues_a_licence_and_the_key_is_returned_once(): void
    {
        $r = $this->restaurant();
        $body = $this->issue($r);

        $key = $body['activation_key'];
        $this->assertMatchesRegularExpression('/^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){3}$/', $key);

        $licence = PosLicence::first();
        $this->assertSame('LIC-2026-'.str_pad((string) $licence->id, 4, '0', STR_PAD_LEFT), $licence->licence_ref);

        // The plaintext key is nowhere in the row — only its HMAC and tail.
        $this->assertSame(LicenceKey::hash($key), $licence->key_hash);
        $this->assertSame(LicenceKey::lastFour($key), $licence->key_last_four);

        // And it is never returned again.
        $sa = User::factory()->superAdmin()->create();
        $show = $this->actingAs($sa)->getJson("/api/admin/pos/licences/{$licence->id}")->assertOk()->json();
        $this->assertArrayNotHasKey('activation_key', $show);
        $this->assertArrayNotHasKey('key_hash', $show['data']);
    }

    public function test_the_signature_verifies_and_the_claims_match_the_client_contract(): void
    {
        $r = $this->restaurant('demo');
        $body = $this->issue($r);

        $payloadB64 = $body['file']['payload'];
        $json = $this->decode($payloadB64);

        // Signed over the DECODED payload bytes — not the base64 string. This is
        // exactly what LicenseVerifier.verifySignature does.
        $this->assertTrue(sodium_crypto_sign_verify_detached(
            $this->decode($body['file']['signature']),
            $json,
            $this->publicKey,
        ));

        $claims = json_decode($json, true);

        // The American spelling is the contract: it is what LicenseClaims
        // .fromJson reads, and changing it breaks every licence already issued.
        $this->assertArrayHasKey('license_id', $claims);
        $this->assertArrayNotHasKey('licence_id', $claims);

        $this->assertSame('demo', $claims['tenant_slug']);
        $this->assertSame('Demo Diner', $claims['tenant_name']);
        $this->assertSame(4, $claims['max_terminals']);
        $this->assertSame(14, $claims['grace_days']);
        $this->assertSame(30, $claims['warn_days']);

        // DeploymentMode.wire values, not enum names.
        $this->assertSame(['cloud', 'branch_server'], $claims['modes']);

        // No `alg` field, ever — that absence is why this is not a JWT.
        $this->assertArrayNotHasKey('alg', $claims);
    }

    public function test_modes_may_not_be_empty(): void
    {
        // An empty modes[] parses to an empty set on the client, every mode then
        // fails, and the terminal reports modeNotLicensed — which reads to a
        // cashier as a bricked till.
        $r = $this->restaurant();
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)
            ->postJson('/api/admin/pos/licences', $this->payload($r, ['modes' => []]))
            ->assertUnprocessable()
            ->assertJsonValidationErrors('modes');
    }

    public function test_platform_staff_below_super_admin_may_not_issue(): void
    {
        $r = $this->restaurant();

        foreach ([RoleEnum::ADMIN, RoleEnum::SALES, RoleEnum::SUPPORT, RoleEnum::MODERATOR] as $role) {
            $staff = User::factory()->create(['role' => $role, 'restaurant_id' => null]);

            $this->actingAs($staff)
                ->postJson('/api/admin/pos/licences', $this->payload($r))
                ->assertForbidden();
        }
    }

    // -------------------------------------------------------------- activation

    public function test_a_terminal_exchanges_the_key_for_the_file(): void
    {
        $r = $this->restaurant('demo');
        $body = $this->issue($r);

        $res = $this->postJson('/api/pos/licence/activate', [
            'key' => $body['activation_key'],
            'tenant_slug' => 'demo',
            'deployment_mode' => 'cloud',
        ])->assertOk()->json();

        // The bare three-key file and nothing else.
        $this->assertSame(['payload', 'signature', 'key_id'], array_keys($res));
        $this->assertSame($body['file'], $res);

        $this->assertNotNull(PosLicence::first()->activated_at);
    }

    public function test_reactivation_is_byte_identical(): void
    {
        $r = $this->restaurant();
        $key = $this->issue($r)['activation_key'];

        $first = $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'demo'])->json();
        $second = $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'demo'])->json();

        // Signing happens once, at issuance. Nothing is re-signed here.
        $this->assertSame($first, $second);
    }

    public function test_the_key_survives_realistic_mistyping(): void
    {
        $r = $this->restaurant();
        $key = $this->issue($r)['activation_key'];

        // Lowercased, spaced instead of hyphenated — an installer reading it
        // off a phone call.
        $mangled = strtolower(str_replace('-', ' ', $key));

        $this->postJson('/api/pos/licence/activate', ['key' => $mangled, 'tenant_slug' => 'demo'])
            ->assertOk();
    }

    public function test_a_licence_issued_to_another_tenant_is_refused(): void
    {
        $r = $this->restaurant('demo');
        $this->restaurant('other');
        $key = $this->issue($r)['activation_key'];

        $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'other'])
            ->assertNotFound()
            ->assertJsonPath('code', 'licence_tenant_mismatch');
    }

    public function test_an_unknown_key_is_not_distinguishable_from_a_wrong_one(): void
    {
        $this->restaurant();

        $this->postJson('/api/pos/licence/activate', ['key' => 'ZZZZ-ZZZZ-ZZZZ-ZZZZ', 'tenant_slug' => 'demo'])
            ->assertNotFound()
            ->assertJsonPath('code', 'licence_not_found');
    }

    public function test_a_revoked_licence_stops_activating(): void
    {
        $r = $this->restaurant();
        $key = $this->issue($r)['activation_key'];
        $licence = PosLicence::first();

        $sa = User::factory()->superAdmin()->create();
        $this->actingAs($sa)
            ->postJson("/api/admin/pos/licences/{$licence->id}/revoke", ['reason' => 'Non-payment'])
            ->assertOk()
            ->assertJsonPath('data.state', 'revoked');

        $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'demo'])
            ->assertForbidden()
            ->assertJsonPath('code', 'licence_revoked');
    }

    // ----------------------------------------------------------------- renewal

    public function test_renewal_writes_a_new_row_and_the_same_key_now_returns_it(): void
    {
        $r = $this->restaurant();
        $issued = $this->issue($r);
        $key = $issued['activation_key'];
        $original = PosLicence::first();

        $sa = User::factory()->superAdmin()->create();
        $renewal = $this->actingAs($sa)->postJson("/api/admin/pos/licences/{$original->id}/renew", [
            'issued_at' => '2027-09-01',
            'expires_at' => '2028-09-01',
        ])->assertCreated()->json();

        // A new row, not a mutated term: the signed artifact is the record of
        // what the customer was sold.
        $this->assertSame(2, PosLicence::count());
        $this->assertTrue($renewal['key_unchanged']);
        $this->assertNull($renewal['activation_key']);
        $this->assertSame($renewal['data']['id'], $original->fresh()->superseded_by_id);

        // Scope is inherited — a renewal that only moves the dates keeps its terms.
        $this->assertSame(4, $renewal['data']['max_terminals']);
        $this->assertSame(['cloud', 'branch_server'], $renewal['data']['modes']);

        // The six-till site retypes nothing: the same key now resolves to the
        // renewal, and the superseded row is no longer handed out.
        $res = $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'demo'])
            ->assertOk()->json();

        $this->assertSame($renewal['file'], $res);
        $this->assertNotSame($issued['file'], $res);
    }

    public function test_rotating_the_key_on_renewal_kills_the_old_one(): void
    {
        $r = $this->restaurant();
        $oldKey = $this->issue($r)['activation_key'];
        $original = PosLicence::first();

        $sa = User::factory()->superAdmin()->create();
        $renewal = $this->actingAs($sa)->postJson("/api/admin/pos/licences/{$original->id}/renew", [
            'issued_at' => '2027-09-01',
            'expires_at' => '2028-09-01',
            'rotate_key' => true,
        ])->assertCreated()->json();

        $this->assertFalse($renewal['key_unchanged']);
        $newKey = $renewal['activation_key'];
        $this->assertNotSame($oldKey, $newKey);

        $this->postJson('/api/pos/licence/activate', ['key' => $oldKey, 'tenant_slug' => 'demo'])
            ->assertNotFound();

        $this->postJson('/api/pos/licence/activate', ['key' => $newKey, 'tenant_slug' => 'demo'])
            ->assertOk();
    }

    // ---------------------------------------------------------------- delivery

    public function test_the_downloaded_file_is_the_same_document_as_the_api_response(): void
    {
        $r = $this->restaurant();
        $body = $this->issue($r);
        $licence = PosLicence::first();

        $sa = User::factory()->superAdmin()->create();
        $download = $this->actingAs($sa)
            ->get("/api/admin/pos/licences/{$licence->id}/download")
            ->assertOk();

        $this->assertStringContainsString(
            'attachment; filename='.$licence->licence_ref.'.xlic',
            $download->headers->get('content-disposition'),
        );

        // The on-premises path and the online path must not be able to drift.
        $this->assertSame($body['file'], json_decode($download->streamedContent(), true));
    }

    public function test_state_reflects_the_term(): void
    {
        $r = $this->restaurant();

        $this->issue($r, ['issued_at' => now()->subYear()->toDateString(), 'expires_at' => now()->addDays(5)->toDateString()]);
        $this->assertSame('expiring_soon', PosLicence::first()->state());

        PosLicence::first()->forceFill(['expires_at' => now()->subDays(3)])->save();
        $this->assertSame('in_grace', PosLicence::first()->state());

        PosLicence::first()->forceFill(['expires_at' => now()->subDays(30)])->save();
        $this->assertSame('expired', PosLicence::first()->state());
    }

    public function test_an_active_licence_cannot_be_deleted(): void
    {
        $r = Restaurant::factory()->create();
        $body = $this->issue($r);
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)
            ->deleteJson("/api/admin/pos/licences/{$body['data']['id']}")
            ->assertStatus(422)
            ->assertJsonPath('code', 'LICENCE_STILL_ACTIVE');

        $this->assertDatabaseHas('pos_licences', ['id' => $body['data']['id']]);
    }

    public function test_a_revoked_licence_can_be_deleted(): void
    {
        $r = Restaurant::factory()->create();
        $body = $this->issue($r);
        $sa = User::factory()->superAdmin()->create();
        $id = $body['data']['id'];

        $this->actingAs($sa)->postJson("/api/admin/pos/licences/{$id}/revoke")->assertOk();
        $this->actingAs($sa)->deleteJson("/api/admin/pos/licences/{$id}")->assertOk();

        $this->assertDatabaseMissing('pos_licences', ['id' => $id]);
    }

    public function test_deleting_a_renewal_unhooks_the_superseded_pointer(): void
    {
        $r = Restaurant::factory()->create();
        $body = $this->issue($r);
        $sa = User::factory()->superAdmin()->create();
        $original = $body['data']['id'];

        $renewal = $this->actingAs($sa)
            ->postJson("/api/admin/pos/licences/{$original}/renew", [
                'issued_at' => now()->toDateString(),
                'expires_at' => now()->addYears(2)->toDateString(),
            ])->assertCreated()->json('data.id');

        // Delete the renewal (revoke it first — it is the active one).
        $this->actingAs($sa)->postJson("/api/admin/pos/licences/{$renewal}/revoke")->assertOk();
        $this->actingAs($sa)->deleteJson("/api/admin/pos/licences/{$renewal}")->assertOk();

        // The original keeps its history but no longer points at a ghost.
        $this->assertDatabaseHas('pos_licences', ['id' => $original, 'superseded_by_id' => null]);
    }
}

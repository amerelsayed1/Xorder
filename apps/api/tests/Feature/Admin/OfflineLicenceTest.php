<?php

namespace Tests\Feature\Admin;

use App\Enums\Feature;
use App\Models\Plan;
use App\Models\PosLicence;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Licensing a customer who is NOT a tenant of this platform.
 *
 * The rule this suite exists to hold: issuing an offline licence creates a
 * LICENCE and nothing else. No restaurant, no admin user, no subscription, no
 * entitlement set. An on-premises customer runs their own database and their
 * sales never leave their building — a tenant row for them would be a record
 * that describes nothing, and would then show up in every tenant count, fleet
 * view and feature sweep the platform runs.
 *
 * The second rule: the till cannot tell the difference. An offline licence is
 * the same signed document, verified the same way, with the same claim keys —
 * the customer's identity simply comes from the licence's own columns instead
 * of from a restaurant.
 */
class OfflineLicenceTest extends TestCase
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

    /** @return array<string,mixed> */
    private function payload(array $overrides = []): array
    {
        return array_merge([
            'customer_name' => 'Al Asima Grill',
            'customer_slug' => 'al-asima',
            'contact_name' => 'Rana Fahmy',
            'contact_email' => 'rana@al-asima.example',
            'contact_phone' => '+201000000000',
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'max_terminals' => 3,
            'max_users' => 8,
            'notes' => 'Paid in full, delivered on a USB stick.',
        ], $overrides);
    }

    private function issue(array $overrides = []): array
    {
        return $this->actingAs(User::factory()->superAdmin()->create())
            ->postJson('/api/admin/pos/licences/offline', $this->payload($overrides))
            ->assertCreated()
            ->json();
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

    // ---------------------------------------------------------------- issuance

    public function test_an_offline_licence_creates_a_licence_and_nothing_else(): void
    {
        $before = User::count();

        $body = $this->issue();

        $this->assertSame('offline', $body['data']['kind']);
        $this->assertNull($body['data']['restaurant']);
        $this->assertSame('Al Asima Grill', $body['data']['client_name']);

        $licence = PosLicence::sole();
        $this->assertNull($licence->restaurant_id);
        $this->assertSame('al-asima', $licence->customer_slug);
        $this->assertSame('Rana Fahmy', $licence->contact_name);

        // The whole point. No tenant, and no account for one either — the
        // Super Admin who issued it is the only user that existed or exists.
        $this->assertSame(0, Restaurant::count());
        $this->assertSame($before + 1, User::count());
    }

    public function test_the_customer_is_signed_into_the_same_claims_a_tenant_would_fill(): void
    {
        $body = $this->issue();
        $claims = $this->claimsOf($body);

        // The till reads `tenant_slug` and `tenant_name` unconditionally. It
        // must not have to know whether a tenant exists behind them.
        $this->assertSame('al-asima', $claims['tenant_slug']);
        $this->assertSame('Al Asima Grill', $claims['tenant_name']);

        $this->assertTrue(sodium_crypto_sign_verify_detached(
            $this->decode($body['file']['signature']),
            $this->decode($body['file']['payload']),
            $this->publicKey,
        ));

        // Still not a JWT.
        $this->assertArrayNotHasKey('alg', $claims);
    }

    public function test_an_offline_licence_can_never_permit_cloud_mode(): void
    {
        // Cloud mode means syncing to a tenant, and this customer has none. A
        // request that asks for it is not an error to report back — it is a
        // value the endpoint simply does not take from input.
        $body = $this->issue(['modes' => ['cloud', 'offline'], 'branch_ids' => [7, 9]]);

        $this->assertSame(['offline'], $this->claimsOf($body)['modes']);
        $this->assertSame([], $this->claimsOf($body)['branch_ids']);
    }

    public function test_an_offline_licence_carries_every_feature_and_no_plan(): void
    {
        // There is no feature ladder on a machine we do not run. Gating
        // features there is a promise the platform cannot keep — the till
        // verifies its own licence, and anyone who cared could patch it. What
        // is sold instead is capacity: devices and people.
        $body = $this->issue([
            // Both are ignored on purpose rather than rejected: the endpoint
            // does not take them from input at all.
            'features' => ['qr_menu'],
            'plan_id' => Plan::create(['name' => 'Pro', 'feature_keys' => ['qr_menu']])->id,
        ]);

        $claims = $this->claimsOf($body);

        $this->assertEqualsCanonicalizing(Feature::values(), $claims['features']);
        $this->assertNull($claims['plan']);
        $this->assertNull(PosLicence::sole()->plan_id);
    }

    public function test_capacity_is_what_the_licence_sells(): void
    {
        $body = $this->issue(['max_terminals' => 3, 'max_users' => 8]);
        $claims = $this->claimsOf($body);

        $this->assertSame(3, $claims['max_terminals']);
        $this->assertSame(8, $claims['max_users']);
        $this->assertSame(8, $body['data']['max_users']);
    }

    public function test_an_unset_user_cap_means_unlimited_rather_than_none(): void
    {
        // A missing claim must not read on the till as "nobody may have an
        // account", which is what a 0 would mean.
        $claims = $this->claimsOf($this->issue(['max_users' => null]));

        $this->assertArrayHasKey('max_users', $claims);
        $this->assertNull($claims['max_users']);
    }

    public function test_a_renewal_keeps_the_capacity_it_was_sold(): void
    {
        $body = $this->issue(['max_terminals' => 3, 'max_users' => 8]);

        $renewal = $this->actingAs(User::factory()->superAdmin()->create())
            ->postJson("/api/admin/pos/licences/{$body['data']['id']}/renew", [
                'issued_at' => '2027-09-01',
                'expires_at' => '2028-09-01',
            ])->assertCreated()->json();

        $this->assertSame(8, $this->claimsOf($renewal)['max_users']);
        $this->assertSame(3, $this->claimsOf($renewal)['max_terminals']);
    }

    public function test_a_slug_already_held_by_a_hosted_tenant_is_refused(): void
    {
        Restaurant::factory()->create(['slug' => 'demo']);

        $this->actingAs(User::factory()->superAdmin()->create())
            ->postJson('/api/admin/pos/licences/offline', $this->payload(['customer_slug' => 'demo']))
            ->assertStatus(422)
            ->assertJsonValidationErrors('customer_slug');
    }

    public function test_the_slug_refusals_are_sentences_not_translation_keys(): void
    {
        // A message pointed at a key that does not exist renders as the key
        // itself — "xorder.errors.slug_taken_by_tenant" in red under the field.
        // That reads to an operator as a crash, and no amount of care in the
        // wording upstream helps if the namespace is wrong.
        Restaurant::factory()->create(['slug' => 'demo']);
        $sa = User::factory()->superAdmin()->create();

        $taken = $this->actingAs($sa)
            ->postJson('/api/admin/pos/licences/offline', $this->payload(['customer_slug' => 'demo']))
            ->assertStatus(422)
            ->json('errors.customer_slug.0');

        $malformed = $this->actingAs($sa)
            ->postJson('/api/admin/pos/licences/offline', $this->payload(['customer_slug' => 'Not A Slug']))
            ->assertStatus(422)
            ->json('errors.customer_slug.0');

        foreach ([$taken, $malformed] as $message) {
            $this->assertStringNotContainsString('xorder.', $message);
            $this->assertMatchesRegularExpression('/[a-z]{4,}\s+[a-z]{2,}/i', $message);
        }
    }

    public function test_only_super_admin_may_issue_one(): void
    {
        $tenant = Restaurant::factory()->create();

        $this->actingAs(User::factory()->restaurantAdmin($tenant->id)->create())
            ->postJson('/api/admin/pos/licences/offline', $this->payload())
            ->assertForbidden();

        $this->assertSame(0, PosLicence::count());
        $this->assertSame(1, Restaurant::count());
    }

    // ---------------------------------------------------------------- lifetime

    public function test_a_lifetime_licence_needs_no_expiry_and_never_reaches_one(): void
    {
        $body = $this->issue(['lifetime' => true, 'expires_at' => null]);

        $this->assertTrue($body['data']['lifetime']);
        // A countdown to a sentinel is a number nobody should read.
        $this->assertNull($body['data']['expires_at']);
        $this->assertNull($body['data']['days_remaining']);
        $this->assertSame('active', $body['data']['state']);

        // But the SIGNED term is a real date, because every till in the field
        // parses `expires_at` unconditionally and a null would not parse.
        $claims = $this->claimsOf($body);
        $this->assertNotNull($claims['expires_at']);
        $this->assertStringStartsWith('2099', $claims['expires_at']);

        $this->assertSame(
            PosLicence::LIFETIME_EXPIRES_AT,
            PosLicence::sole()->expires_at->format('Y-m-d H:i:s'),
        );
    }

    public function test_a_term_licence_still_needs_its_expiry(): void
    {
        $this->actingAs(User::factory()->superAdmin()->create())
            ->postJson('/api/admin/pos/licences/offline', $this->payload(['expires_at' => null]))
            ->assertStatus(422)
            ->assertJsonValidationErrors('expires_at');
    }

    // -------------------------------------------------------------- activation

    public function test_a_till_activates_with_the_key_alone(): void
    {
        // The wizard asks for the licence FIRST — the licence is what tells the
        // till which tenant it serves — so at this moment there is no slug to
        // send. Demanding one made "Activate online" impossible to satisfy.
        $body = $this->issue();

        // The signed file, plus where this till gets its verdict (R2): an
        // offline licence's tills trust the file.
        $this->postJson('/api/pos/licence/activate', ['key' => $body['activation_key']])
            ->assertOk()
            ->assertExactJson($body['file'] + ['enforcement' => 'offline']);

        $this->assertNotNull(PosLicence::sole()->activated_at);
    }

    public function test_a_cloud_licence_activates_with_the_key_alone_too(): void
    {
        $restaurant = Restaurant::factory()->create(['slug' => 'demo', 'name_en' => 'Demo Diner']);

        $cloud = $this->actingAs(User::factory()->superAdmin()->create())
            ->postJson('/api/admin/pos/licences', [
                'restaurant_id' => $restaurant->id,
                'issued_at' => '2026-09-01',
                'expires_at' => '2027-09-01',
                'modes' => ['cloud'],
            ])->assertCreated()->json();

        $this->postJson('/api/pos/licence/activate', ['key' => $cloud['activation_key']])
            ->assertOk()
            ->assertExactJson($cloud['file'] + ['enforcement' => 'online']);
    }

    public function test_a_slug_that_is_offered_is_still_checked(): void
    {
        $body = $this->issue();
        $key = $body['activation_key'];

        // Optional is not the same as ignored: an installer who types the wrong
        // customer's identifier is still told, in both directions.
        $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'someone-else'])
            ->assertNotFound()
            ->assertJsonPath('code', 'licence_tenant_mismatch');

        $this->postJson('/api/pos/licence/activate', ['key' => $key, 'tenant_slug' => 'al-asima'])
            ->assertOk();
    }

    public function test_a_revoked_offline_licence_still_refuses_activation(): void
    {
        $body = $this->issue();
        $sa = User::factory()->superAdmin()->create();

        $this->actingAs($sa)->postJson("/api/admin/pos/licences/{$body['data']['id']}/revoke")->assertOk();

        $this->postJson('/api/pos/licence/activate', ['key' => $body['activation_key']])
            ->assertForbidden()
            ->assertJsonPath('code', 'licence_revoked');
    }

    // ------------------------------------------------------- list and delivery

    public function test_both_kinds_share_one_list_and_the_kind_filters_it(): void
    {
        $this->issue();

        $restaurant = Restaurant::factory()->create(['slug' => 'demo']);
        $sa = User::factory()->superAdmin()->create();
        $this->actingAs($sa)->postJson('/api/admin/pos/licences', [
            'restaurant_id' => $restaurant->id,
            'issued_at' => '2026-09-01',
            'expires_at' => '2027-09-01',
            'modes' => ['cloud'],
        ])->assertCreated();

        // A tenant-less row in a list that eager-loads `restaurant` is exactly
        // where a null dereference would land.
        $all = $this->actingAs($sa)->getJson('/api/admin/pos/licences')->assertOk()->json('data');
        $this->assertCount(2, $all);

        $offline = $this->actingAs($sa)->getJson('/api/admin/pos/licences?kind=offline')->assertOk()->json('data');
        $this->assertCount(1, $offline);
        $this->assertSame('Al Asima Grill', $offline[0]['client_name']);

        $cloud = $this->actingAs($sa)->getJson('/api/admin/pos/licences?kind=cloud')->assertOk()->json('data');
        $this->assertCount(1, $cloud);
        $this->assertSame('demo', $cloud[0]['restaurant']['slug']);

        $found = $this->actingAs($sa)->getJson('/api/admin/pos/licences?search=asima')->assertOk()->json('data');
        $this->assertCount(1, $found);
    }

    public function test_the_file_downloads_and_is_the_same_document(): void
    {
        $body = $this->issue();

        $download = $this->actingAs(User::factory()->superAdmin()->create())
            ->get("/api/admin/pos/licences/{$body['data']['id']}/download")
            ->assertOk();

        // The delivery path that matters here: a site with no internet gets
        // this file on a stick, and it must be the document that was signed.
        $this->assertSame($body['file'], json_decode($download->streamedContent(), true));
    }

    public function test_a_renewal_keeps_the_customer_and_the_kind(): void
    {
        $body = $this->issue();
        $sa = User::factory()->superAdmin()->create();

        $renewal = $this->actingAs($sa)
            ->postJson("/api/admin/pos/licences/{$body['data']['id']}/renew", [
                'issued_at' => '2027-09-01',
                'expires_at' => '2028-09-01',
            ])->assertCreated()->json();

        $this->assertSame('offline', $renewal['data']['kind']);
        $this->assertSame('Al Asima Grill', $renewal['data']['customer_name']);
        $this->assertSame('al-asima', $this->claimsOf($renewal)['tenant_slug']);
        $this->assertNull(PosLicence::latest('id')->first()->restaurant_id);

        // The key is unchanged, so a six-till site retypes nothing.
        $this->assertTrue($renewal['key_unchanged']);
        $this->postJson('/api/pos/licence/activate', ['key' => $body['activation_key']])
            ->assertOk()
            // A renewal keeps the kind, and so how it is enforced.
            ->assertExactJson($renewal['file'] + ['enforcement' => 'offline']);
    }
}

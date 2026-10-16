<?php

namespace Tests\Feature\Pos;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * GET /api/pos/licence/issuer — the public half of the signing key, for a
 * release build of the till to be compiled with (audit S1-2, 16 Oct 2026).
 */
class LicenceIssuerTest extends TestCase
{
    use RefreshDatabase;

    public function test_it_publishes_the_public_key_and_key_id_without_a_credential(): void
    {
        $pair = sodium_crypto_sign_keypair();
        config([
            'licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair)),
            'licence.key_id' => 'v7',
        ]);

        $this->getJson('/api/pos/licence/issuer')
            ->assertOk()
            ->assertExactJson([
                'key_id' => 'v7',
                'public_key' => base64_encode(sodium_crypto_sign_publickey($pair)),
                'algorithm' => 'ed25519',
            ]);
    }

    public function test_it_never_publishes_the_secret_half(): void
    {
        $pair = sodium_crypto_sign_keypair();
        config(['licence.signing_key' => base64_encode(sodium_crypto_sign_secretkey($pair))]);

        $body = $this->getJson('/api/pos/licence/issuer')->assertOk()->getContent();

        $this->assertStringNotContainsString(base64_encode(sodium_crypto_sign_secretkey($pair)), $body);
        $this->assertSame(SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES, strlen(base64_decode(json_decode($body, true)['public_key'])));
    }

    public function test_an_unconfigured_platform_answers_503_not_an_empty_key(): void
    {
        config(['licence.signing_key' => null]);

        $this->getJson('/api/pos/licence/issuer')
            ->assertStatus(503)
            ->assertJsonPath('code', 'licence_issuer_unconfigured');
    }
}

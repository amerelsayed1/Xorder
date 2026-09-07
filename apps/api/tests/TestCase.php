<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;

abstract class TestCase extends BaseTestCase
{
    /**
     * A throwaway Ed25519 pair, minted once per test process.
     *
     * Creating a tenant now issues its POS licence in the same transaction
     * (owner decision, 2026-09-05), and LicenceIssuer refuses to sign without
     * a key — so without this, every test that creates a restaurant would die
     * on a missing LICENCE_SIGNING_KEY rather than on anything it meant to
     * assert. Generated at runtime rather than checked into phpunit.xml so no
     * secret-shaped string lives in the repository.
     *
     * @var array{public: string, secret: string}|null
     */
    private static ?array $licenceKeypair = null;

    protected function setUp(): void
    {
        parent::setUp();

        if (self::$licenceKeypair === null) {
            $pair = sodium_crypto_sign_keypair();
            self::$licenceKeypair = [
                'public' => sodium_crypto_sign_publickey($pair),
                'secret' => sodium_crypto_sign_secretkey($pair),
            ];
        }

        config([
            'licence.signing_key' => base64_encode(self::$licenceKeypair['secret']),
            'licence.key_id' => 'v1',
        ]);
    }

    /** The public half, for tests that verify a signed licence file. */
    protected function licencePublicKey(): string
    {
        return self::$licenceKeypair['public'];
    }
}

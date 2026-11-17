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

    /**
     * Refuse to run against anything but a throwaway database.
     *
     * phpunit.xml asks for SQLite `:memory:`, but a variable already present in
     * the process environment (for example one injected by `doppler run` for a
     * local run, or exported in a shell) beats it, and RefreshDatabase would then
     * wipe whatever database that points at. This check runs right after the
     * application boots and before any trait touches the database.
     */
    public function createApplication()
    {
        // Before the app boots (booting can already reach a remote database or Redis):
        // a non-sqlite connection, a connection URL or a non-array cache in the
        // process environment means this is not a throwaway run.
        $env = static fn (string $k): ?string => ($v = $_SERVER[$k] ?? $_ENV[$k] ?? getenv($k)) === false ? null : $v;
        foreach (['DB_CONNECTION' => 'sqlite', 'CACHE_STORE' => 'array'] as $key => $allowed) {
            if (($v = $env($key)) !== null && $v !== '' && $v !== $allowed) {
                throw new \RuntimeException("Refusing to run tests: {$key}={$v} is set in the environment (expected {$allowed}). Unset it, or the Doppler config that injects it.");
            }
        }
        foreach (['DB_URL', 'DATABASE_URL', 'DB_HOST'] as $key) {
            if (($v = $env($key)) !== null && $v !== '') {
                throw new \RuntimeException("Refusing to run tests: {$key} is set in the environment. Unset it, or the Doppler config that injects it.");
            }
        }

        $app = parent::createApplication();

        $db = $app['config']->get('database.default');
        $name = $app['config']->get("database.connections.{$db}.database");
        $cache = $app['config']->get('cache.default');

        if ($db !== 'sqlite' || $name !== ':memory:' || $cache !== 'array') {
            throw new \RuntimeException(sprintf(
                'Refusing to run tests: expected sqlite :memory: with the array cache, got database "%s" (%s) and cache "%s". '
                .'Unset DB_*/CACHE_STORE in your environment (or the Doppler config) before running the suite.',
                $db,
                is_string($name) ? $name : 'n/a',
                $cache,
            ));
        }

        return $app;
    }

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

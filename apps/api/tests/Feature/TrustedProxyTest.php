<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * request()->ip() must reflect who actually connected, not what they claimed.
 *
 * It is the input to the login rate limiter and to branch Wi-Fi presence
 * matching, so a caller who can choose their own apparent address can both
 * sidestep throttling and be recorded as standing inside a restaurant they have
 * never visited.
 *
 * The chain in production is: client -> edge nginx -> app nginx -> PHP. Every
 * hop is private and the real client is public, so trusting only the private
 * ranges makes Symfony discard the hops and stop at the first public entry.
 */
class TrustedProxyTest extends TestCase
{
    use RefreshDatabase;

    /** Anything reachable that echoes the resolved client IP back to us. */
    private function resolvedIp(array $server, array $headers = []): string
    {
        $this->app['router']->get('/_test/ip', fn () => response()->json(['ip' => request()->ip()]));

        return $this->withServerVariables($server)
            ->getJson('/_test/ip', $headers)
            ->assertOk()
            ->json('ip');
    }

    public function test_a_forged_forwarded_header_from_a_public_client_is_ignored(): void
    {
        // The attack: a diner sends the branch's own Wi-Fi address so their
        // session is stamped as on-premises.
        $ip = $this->resolvedIp(
            ['REMOTE_ADDR' => '185.93.2.251'],
            ['X-Forwarded-For' => '203.0.113.10'],
        );

        $this->assertSame('185.93.2.251', $ip, 'A public peer is the client; its claimed header must be discarded.');
    }

    public function test_a_genuine_proxy_chain_still_resolves_the_real_client(): void
    {
        // What production actually looks like: the edge appends nothing forged,
        // and the last hop into PHP is the app's own nginx on a private address.
        $ip = $this->resolvedIp(
            ['REMOTE_ADDR' => '172.26.0.5'],
            ['X-Forwarded-For' => '41.238.10.77'],
        );

        $this->assertSame('41.238.10.77', $ip, 'Private hops are stripped; the public client remains.');
    }

    public function test_a_forged_entry_prepended_to_a_genuine_chain_loses_to_the_real_client(): void
    {
        // Belt and braces: even if an edge appended rather than replaced, the
        // forged value sits to the LEFT of the genuine client, and the
        // right-to-left walk reaches the genuine one first.
        $ip = $this->resolvedIp(
            ['REMOTE_ADDR' => '172.26.0.5'],
            ['X-Forwarded-For' => '203.0.113.10, 41.238.10.77'],
        );

        $this->assertSame('41.238.10.77', $ip);
    }

    public function test_forwarded_proto_from_the_private_edge_is_still_honoured(): void
    {
        // The reason trustProxies exists at all: without it the app generates
        // http:// URLs behind a TLS-terminating proxy.
        $this->app['router']->get('/_test/secure', fn () => response()->json(['secure' => request()->isSecure()]));

        $this->withServerVariables(['REMOTE_ADDR' => '172.26.0.5'])
            ->getJson('/_test/secure', ['X-Forwarded-Proto' => 'https'])
            ->assertOk()
            ->assertJsonPath('secure', true);
    }
}

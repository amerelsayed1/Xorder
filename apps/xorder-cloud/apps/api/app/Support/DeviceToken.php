<?php

namespace App\Support;

use Illuminate\Support\Facades\Config;

/**
 * The terminal's own credential (POS-BE-011, Option C): `xdt_` + 64 lowercase
 * hex chars, issued once at claim/register, shown once, stored only as an
 * HMAC-SHA256 — the same searchable-but-not-reversible discipline as
 * LicenceKey. No TTL: the lifecycle is terminal revocation, with a rotation
 * endpoint whose old token stays valid 24h so a crash between receiving and
 * persisting a new token cannot brick the till.
 */
final class DeviceToken
{
    public const PREFIX = 'xdt_';

    public static function generate(): string
    {
        return self::PREFIX.bin2hex(random_bytes(32));
    }

    public static function looksValid(?string $token): bool
    {
        return is_string($token)
            && str_starts_with($token, self::PREFIX)
            && preg_match('/^[0-9a-f]{64}$/', substr($token, strlen(self::PREFIX))) === 1;
    }

    public static function hash(string $token): string
    {
        return hash_hmac('sha256', $token, self::secret());
    }

    private static function secret(): string
    {
        $key = (string) Config::get('app.key');

        return str_starts_with($key, 'base64:')
            ? base64_decode(substr($key, 7))
            : $key;
    }
}

<?php

namespace App\Support;

/**
 * Credentials of the waiter wire (POS-BE-033). Own prefixes so a waiter token
 * can never be mistaken for a till's `xdt_` device token, hashed the same way
 * (HMAC-SHA256 under the app key, searchable but not reversible).
 */
final class WaiterToken
{
    public const DEVICE_PREFIX = 'xwd_';

    public const SESSION_PREFIX = 'xws_';

    public static function device(): string
    {
        return self::DEVICE_PREFIX.bin2hex(random_bytes(32));
    }

    public static function session(): string
    {
        return self::SESSION_PREFIX.bin2hex(random_bytes(32));
    }

    public static function looksValid(?string $token, string $prefix): bool
    {
        return is_string($token)
            && str_starts_with($token, $prefix)
            && preg_match('/^[0-9a-f]{64}$/', substr($token, strlen($prefix))) === 1;
    }

    public static function hash(string $token): string
    {
        return DeviceToken::hash($token);
    }
}

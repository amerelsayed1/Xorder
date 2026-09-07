<?php

namespace App\Support;

/**
 * POS PIN hashing (POS-BE-024, amended 2026-09-02): PBKDF2-HMAC-SHA256,
 * 120000 iterations, 16-byte salt, 32-byte key — chosen because the Flutter
 * client already ships a tested PBKDF2 verifier (lib/core/security/pin_hash
 * .dart) and stores (salt, hash) base64 pairs; bcrypt would have added a
 * client dependency for no security gain at a 4-6 digit keyspace.
 *
 * Stated plainly in the contract and repeated here: a digit PIN is offline
 * brute-forceable from a stolen hash regardless of algorithm. The containment
 * is blast radius — the PIN opens only the till, never login or the dashboard,
 * and clearing it locks the cashier out of every till at next sync.
 */
final class PosPin
{
    public const ALGORITHM = 'pbkdf2_sha256';

    public const ITERATIONS = 120000;

    private const SALT_BYTES = 16;

    private const KEY_BYTES = 32;

    /** @return array{salt: string, hash: string} base64 pair, fresh salt per set */
    public static function make(string $pin): array
    {
        $salt = random_bytes(self::SALT_BYTES);

        return [
            'salt' => base64_encode($salt),
            'hash' => base64_encode(hash_pbkdf2('sha256', $pin, $salt, self::ITERATIONS, self::KEY_BYTES, true)),
        ];
    }

    /** The wire block bootstrap emits inside staff[] (null when no PIN set). */
    public static function wire(?string $salt, ?string $hash): ?array
    {
        if ($salt === null || $hash === null) {
            return null;
        }

        return [
            'algorithm' => self::ALGORITHM,
            'iterations' => self::ITERATIONS,
            'salt' => $salt,
            'hash' => $hash,
        ];
    }
}

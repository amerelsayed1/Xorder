<?php

namespace App\Support;

use Illuminate\Support\Facades\Config;

/**
 * The human-typed activation key for a POS licence (POS-BE-015 §5).
 *
 * Sixteen Crockford base32 characters in four groups: XO4T-9WQM-2K7H-BR5N.
 *
 * Crockford because it excludes I, L, O and U — which is what makes a key
 * readable down a phone line to an installer standing at a till in a noisy
 * restaurant. That is the actual delivery channel for the on-premises case, so
 * it governs the alphabet.
 */
final class LicenceKey
{
    /** Crockford base32: no I, no L, no O, no U. */
    private const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    private const GROUPS = 4;

    private const GROUP_SIZE = 4;

    /** Arabic-Indic and Eastern Arabic-Indic digits, folded on input. */
    private const ARABIC_DIGITS = [
        '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
        '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
        '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
        '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
    ];

    /**
     * Mint a fresh key. Uses random_int, which draws from the CSPRNG — this is
     * a credential, not an identifier.
     */
    public static function generate(): string
    {
        $groups = [];

        for ($g = 0; $g < self::GROUPS; $g++) {
            $chunk = '';
            for ($i = 0; $i < self::GROUP_SIZE; $i++) {
                $chunk .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
            }
            $groups[] = $chunk;
        }

        return implode('-', $groups);
    }

    /**
     * Canonical form used for hashing and comparison.
     *
     * Folds the transcription errors Crockford exists to survive: I and L read
     * as 1, O reads as 0. Also folds Arabic-Indic digits, because the operator
     * typing this may be on an Arabic keyboard.
     */
    public static function normalise(string $key): string
    {
        $key = strtr($key, self::ARABIC_DIGITS);
        $key = strtoupper($key);
        $key = preg_replace('/[^0-9A-Z]/', '', $key) ?? '';

        return strtr($key, ['I' => '1', 'L' => '1', 'O' => '0']);
    }

    /**
     * Keyed hash for storage and lookup.
     *
     * HMAC rather than a password hash because activation must find the row
     * from the key alone; see the column comment on pos_licences.key_hash.
     */
    public static function hash(string $key): string
    {
        return hash_hmac('sha256', self::normalise($key), self::secret());
    }

    /** The tail shown in the dashboard list, so the key itself need not be held. */
    public static function lastFour(string $key): string
    {
        return substr(self::normalise($key), -4);
    }

    /** Whether a typed string could be a key at all, before any lookup. */
    public static function looksValid(string $key): bool
    {
        return strlen(self::normalise($key)) === self::GROUPS * self::GROUP_SIZE;
    }

    private static function secret(): string
    {
        $key = (string) Config::get('app.key');

        return str_starts_with($key, 'base64:')
            ? base64_decode(substr($key, 7))
            : $key;
    }
}

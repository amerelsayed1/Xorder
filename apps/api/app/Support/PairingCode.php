<?php

namespace App\Support;

use Illuminate\Support\Facades\Config;

/**
 * The claim credential (POS-BE-023): 8 Crockford base32 characters displayed
 * XXXX-XXXX. Same alphabet and normalisation as LicenceKey — no I/L/O/U, fold
 * Arabic-Indic digits — because the delivery channel is the same: a human
 * reading it off a dashboard to an installer at a till. Hashed at rest,
 * single-use, 24h TTL, never logged.
 */
final class PairingCode
{
    private const ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

    public const LENGTH = 8;

    public const TTL_HOURS = 24;

    private const ARABIC_DIGITS = [
        '٠' => '0', '١' => '1', '٢' => '2', '٣' => '3', '٤' => '4',
        '٥' => '5', '٦' => '6', '٧' => '7', '٨' => '8', '٩' => '9',
        '۰' => '0', '۱' => '1', '۲' => '2', '۳' => '3', '۴' => '4',
        '۵' => '5', '۶' => '6', '۷' => '7', '۸' => '8', '۹' => '9',
    ];

    /** CSPRNG — this is a credential, not an identifier. */
    public static function generate(): string
    {
        $code = '';
        for ($i = 0; $i < self::LENGTH; $i++) {
            $code .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
        }

        return substr($code, 0, 4).'-'.substr($code, 4);
    }

    public static function normalise(string $code): string
    {
        $code = strtr($code, self::ARABIC_DIGITS);
        $code = strtoupper($code);
        $code = preg_replace('/[^0-9A-Z]/', '', $code) ?? '';

        return strtr($code, ['I' => '1', 'L' => '1', 'O' => '0']);
    }

    public static function hash(string $code): string
    {
        return hash_hmac('sha256', self::normalise($code), self::secret());
    }

    private static function secret(): string
    {
        $key = (string) Config::get('app.key');

        return str_starts_with($key, 'base64:')
            ? base64_decode(substr($key, 7))
            : $key;
    }
}

<?php

namespace App\Support;

/**
 * Arabic-Indic (٠-٩) and Persian (۰-۹) digits to Latin, for input that is
 * about to be validated as a number (XORD-004).
 *
 * The dashboards fold digits in the browser, but the API is the authority and
 * must not depend on which client sent the request: the POS, an import, a
 * script. This works on characters, never on values, so a phone number keeps
 * its leading zeros.
 *
 * `٫` (the Arabic decimal mark) becomes `.`. `٬` (the Arabic thousands mark) is
 * deliberately left alone: dropping it would be guessing that "١٬٢٥٠" means
 * 1250, and a number that is not plainly a number should fail validation.
 */
final class Digits
{
    private const FROM = [
        '٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩',
        '۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹',
        '٫',
    ];

    private const TO = [
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        '0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        '.',
    ];

    public static function latin(string $value): string
    {
        return str_replace(self::FROM, self::TO, $value);
    }
}

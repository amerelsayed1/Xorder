<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;
use libphonenumber\NumberParseException;
use libphonenumber\PhoneNumberType;
use libphonenumber\PhoneNumberUtil;

/**
 * Validates a phone number against libphonenumber's per-country rules, so each
 * country's own length and format (its "max count") is respected.
 *
 * Numbers written in international E.164 format ("+9665...") are validated
 * against the country their prefix identifies. Numbers written in local format
 * ("01xxxxxxxxx") are parsed against the platform's default country
 * (config: platform.default_phone_country), which can be overridden per rule.
 *
 * Arabic-Indic and Persian digits are normalized to Latin before parsing, so a
 * customer typing "٠١٠..." is accepted the same as "010...".
 *
 * By default only mobile-capable numbers pass (a phone number is meant for
 * WhatsApp/SMS contact). Call allowLandline() on fields that legitimately hold
 * a business landline (e.g. a restaurant's public phone).
 */
class MobileNumber implements ValidationRule
{
    private bool $allowLandline = false;

    public function __construct(private ?string $defaultCountry = null) {}

    /**
     * Also accept fixed-line (landline) numbers, not just mobile-capable ones.
     */
    public function allowLandline(): static
    {
        $this->allowLandline = true;

        return $this;
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        // Presence is governed by required/nullable — an empty value is not our
        // concern here.
        if ($value === null || $value === '' || (is_string($value) && trim($value) === '')) {
            return;
        }

        if (! is_string($value)) {
            $fail(__('xorder.validation.phone_invalid'));

            return;
        }

        $normalized = self::normalizeDigits($value);
        $region = $this->defaultCountry ?? config('platform.default_phone_country', 'EG');
        $util = PhoneNumberUtil::getInstance();

        try {
            $proto = $util->parse($normalized, $region);
        } catch (NumberParseException) {
            $fail(__('xorder.validation.phone_invalid'));

            return;
        }

        if (! $util->isValidNumber($proto)) {
            $fail(__('xorder.validation.phone_invalid'));

            return;
        }

        $allowed = [PhoneNumberType::MOBILE, PhoneNumberType::FIXED_LINE_OR_MOBILE];
        if ($this->allowLandline) {
            $allowed[] = PhoneNumberType::FIXED_LINE;
        }

        if (! in_array($util->getNumberType($proto), $allowed, true)) {
            $fail(__('xorder.validation.phone_invalid'));
        }
    }

    /**
     * Convert Arabic-Indic (٠-٩) and Persian (۰-۹) digits to Latin (0-9).
     */
    public static function normalizeDigits(string $value): string
    {
        $arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $persian = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];
        $latin = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

        return trim(str_replace($persian, $latin, str_replace($arabic, $latin, $value)));
    }
}

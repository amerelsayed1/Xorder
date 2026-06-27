<?php

namespace App\Support;

class Localize
{
    /**
     * Pick the value for the requested language, falling back to the other
     * language when the preferred one is empty.
     */
    public static function pick(?string $ar, ?string $en, string $lang): ?string
    {
        if ($lang === 'ar') {
            return filled($ar) ? $ar : $en;
        }

        return filled($en) ? $en : $ar;
    }

    /** Convert Western digits to Arabic-Indic when rendering an Arabic page. */
    public static function digits(string|int|float|null $value, string $lang): string
    {
        $value = (string) $value;

        if ($lang !== 'ar') {
            return $value;
        }

        return strtr($value, [
            '0' => '٠', '1' => '١', '2' => '٢', '3' => '٣', '4' => '٤',
            '5' => '٥', '6' => '٦', '7' => '٧', '8' => '٨', '9' => '٩',
        ]);
    }
}

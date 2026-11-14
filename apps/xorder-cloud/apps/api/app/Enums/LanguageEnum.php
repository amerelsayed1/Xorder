<?php

namespace App\Enums;

enum LanguageEnum: string
{
    case AR = 'ar';
    case EN = 'en';

    public function isRtl(): bool
    {
        return $this === self::AR;
    }

    public function dir(): string
    {
        return $this->isRtl() ? 'rtl' : 'ltr';
    }
}

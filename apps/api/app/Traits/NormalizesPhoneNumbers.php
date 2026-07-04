<?php

namespace App\Traits;

/**
 * Automatically converts Arabic numerals to English numerals in phone fields.
 *
 * Usage: Add `use NormalizesPhoneNumbers;` to your model and it will
 * automatically normalize any phone-related fields on create/update.
 */
trait NormalizesPhoneNumbers
{
    /**
     * Boot the trait - register event listeners.
     */
    protected static function bootNormalizesPhoneNumbers(): void
    {
        static::creating(function ($model) {
            $model->normalizePhoneFields();
        });

        static::updating(function ($model) {
            $model->normalizePhoneFields();
        });
    }

    /**
     * Normalize phone and whatsapp_number fields.
     */
    public function normalizePhoneFields(): void
    {
        if (isset($this->attributes['phone'])) {
            $this->attributes['phone'] = $this->convertToEnglishDigits($this->attributes['phone']);
        }

        if (isset($this->attributes['whatsapp_number'])) {
            $this->attributes['whatsapp_number'] = $this->convertToEnglishDigits($this->attributes['whatsapp_number']);
        }
    }

    /**
     * Convert Arabic and Persian digits to English digits.
     */
    private function convertToEnglishDigits(?string $value): ?string
    {
        if (is_null($value)) {
            return null;
        }

        // Arabic-Indic digits (٠-٩) to English (0-9)
        $arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

        // Persian/Farsi digits (۰-۹) to English (0-9)
        $persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

        $value = str_replace($arabicDigits, $englishDigits, $value);
        $value = str_replace($persianDigits, $englishDigits, $value);

        return $value;
    }
}

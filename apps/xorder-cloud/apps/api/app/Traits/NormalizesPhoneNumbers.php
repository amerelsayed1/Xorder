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
     * Phone-like attributes normalized on save. A model may override this by
     * declaring a `$phoneFields` property to change the covered columns.
     *
     * @var list<string>
     */
    protected array $defaultPhoneFields = ['phone', 'whatsapp_number', 'whatsapp', 'customer_phone'];

    /**
     * Normalize every phone-like field the model actually has.
     */
    public function normalizePhoneFields(): void
    {
        foreach ($this->phoneFields ?? $this->defaultPhoneFields as $field) {
            if (isset($this->attributes[$field])) {
                $this->attributes[$field] = $this->convertToEnglishDigits($this->attributes[$field]);
            }
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

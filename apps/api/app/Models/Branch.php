<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Model;

class Branch extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'name_ar',
        'name_en',
        'address',
        'phone',
        'whatsapp_number',
        'opening_hours',
        'map_url',
        'latitude',
        'longitude',
        'is_open',
        'is_active',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'is_open' => 'boolean',
            'is_active' => 'boolean',
            'latitude' => 'float',
            'longitude' => 'float',
        ];
    }

    protected function phone(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    protected function whatsappNumber(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    private function normalizePhoneDigits(?string $value): ?string
    {
        if (is_null($value)) {
            return null;
        }

        $arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
        $persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

        $value = str_replace($arabicDigits, $englishDigits, $value);

        return str_replace($persianDigits, $englishDigits, $value);
    }
}

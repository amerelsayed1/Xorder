<?php

namespace App\Models;

use App\Enums\CurrencyEnum;
use Illuminate\Database\Eloquent\Model;

class Plan extends Model
{
    protected $fillable = [
        'name',
        'price',
        'currency',
        'feature_keys',
        'max_items',
        'max_categories',
        'max_branches',
        'max_staff',
        'max_terminals',
        'is_active',
        'is_recommended',
        'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'price' => 'decimal:2',
            'currency' => CurrencyEnum::class,
            'feature_keys' => 'array',
            'is_active' => 'boolean',
            'is_recommended' => 'boolean',
        ];
    }

    /**
     * The plan's entitlement set as a requested flag map (key => true), ready
     * for Feature::resolve. Unknown/legacy plans with no feature_keys yield an
     * empty map, which the entitlement service treats as "no features".
     *
     * @return array<string,bool>
     */
    public function featureMap(): array
    {
        return collect($this->feature_keys ?? [])
            ->mapWithKeys(fn (string $key) => [$key => true])
            ->all();
    }
}

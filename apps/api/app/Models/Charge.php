<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * POS-BE-013: an additional charge (service charge, delivery fee). Exactly one
 * of rate_bp (percent kind, basis points) / amount_minor (fixed kind, minor
 * units) is non-null — the FormRequest enforces it. `taxable` says whether tax
 * applies on top of this charge.
 */
class Charge extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['name', 'kind', 'rate_bp', 'amount_minor', 'taxable', 'applies_to', 'sort_order'];

    protected function casts(): array
    {
        return [
            'rate_bp' => 'integer',
            'amount_minor' => 'integer',
            'taxable' => 'boolean',
            'applies_to' => 'array',
            'sort_order' => 'integer',
        ];
    }
}

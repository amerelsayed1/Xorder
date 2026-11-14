<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * POS-BE-013: a tax rule. rate_bp is integer basis points (1400 = 14%) — never
 * a float. `mode` says whether the rate is added on top (exclusive) or already
 * contained in prices (inclusive). applies_to scopes by order type / branch /
 * category / item; [] or absent means "all".
 */
class TaxRule extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['name', 'rate_bp', 'mode', 'applies_to', 'sort_order'];

    protected function casts(): array
    {
        return [
            'rate_bp' => 'integer',
            'applies_to' => 'array',
            'sort_order' => 'integer',
        ];
    }
}

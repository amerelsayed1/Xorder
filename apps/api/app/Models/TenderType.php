<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * POS-BE-013: a way money arrives. kind cash|card|external|other, so v1 can
 * record a card taken on a standalone bank terminal without pretending to be a
 * processor. Never hard-deleted once referenced — DELETE deactivates, so
 * historical order_payments keep their FK.
 */
class TenderType extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['name', 'kind', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }
}

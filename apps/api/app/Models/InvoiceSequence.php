<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * POS-BE-008: the per-(tenant, branch, period) invoice counter. Only ever
 * touched under lockForUpdate() inside the order-creation transaction — see
 * InvoiceSequenceService.
 */
class InvoiceSequence extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [];

    protected function casts(): array
    {
        return ['next_value' => 'integer'];
    }
}

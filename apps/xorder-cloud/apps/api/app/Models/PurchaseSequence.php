<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/** CB-09 slice b: the per-business, per-year PO counter. Written only by PurchaseSequenceService. */
class PurchaseSequence extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return ['next_value' => 'integer'];
    }
}

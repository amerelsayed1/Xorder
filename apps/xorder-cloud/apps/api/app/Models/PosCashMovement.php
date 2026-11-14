<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * POS-BE-009: cash in / cash out against an open shift. A future `payouts`
 * concept arrives as another `reason` value here, never a new term in the
 * expected-cash formula (A3).
 */
class PosCashMovement extends Model
{
    use Auditable, BelongsToRestaurant;

    /** Created exclusively by PosShiftService via forceFill. */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'amount_minor' => 'integer',
            'occurred_at' => 'datetime',
            'received_at' => 'datetime',
        ];
    }

    public function shift(): BelongsTo
    {
        return $this->belongsTo(PosShift::class, 'pos_shift_id');
    }
}

<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * POS-BE-009: one cashier session on one terminal. opened_at/closed_at are
 * CLIENT times stored as sent; received_at is the server's observation. One
 * open shift per terminal, enforced by PosShiftService under a terminal lock.
 */
class PosShift extends Model
{
    use Auditable, BelongsToRestaurant;

    public const STATUS_OPEN = 'open';

    public const STATUS_CLOSED = 'closed';

    /** Created exclusively by PosShiftService via forceFill. */
    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'opened_at' => 'datetime',
            'closed_at' => 'datetime',
            'received_at' => 'datetime',
            'opening_float_minor' => 'integer',
            'counted_cash_minor' => 'integer',
            'expected_cash_minor' => 'integer',
            'variance_minor' => 'integer',
            'denominations' => 'array',
        ];
    }

    public function terminal(): BelongsTo
    {
        return $this->belongsTo(PosTerminal::class, 'pos_terminal_id');
    }

    /** The cashier who opened the shift — named on the back-office summary. */
    public function openedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'opened_by_id');
    }

    public function cashMovements(): HasMany
    {
        return $this->hasMany(PosCashMovement::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }

    public function isOpen(): bool
    {
        return $this->status === self::STATUS_OPEN;
    }
}

<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/**
 * POS-BE-010: money given back, as its own document. The original order is
 * never touched — this record references it.
 *
 * `kind` is the platform's axis and NOT the till's `pos_refunds.kind`
 * (`full|partial`, which the platform derives for itself from the counters):
 *
 *   refund  money was handed back to a customer
 *   void    the sale was reversed in full, in the same shift, before its
 *           takings were reported
 *
 * Created exclusively by PosRefundService via forceFill, like PosShift.
 */
class PosRefund extends Model
{
    use Auditable, BelongsToRestaurant;

    public const KIND_REFUND = 'refund';

    public const KIND_VOID = 'void';

    protected $fillable = [];

    protected function casts(): array
    {
        return [
            'total_minor' => 'integer',
            'occurred_at' => 'datetime',
            'received_at' => 'datetime',
        ];
    }

    protected function auditLabel(): string
    {
        return (string) ($this->credit_note_number ?: $this->id);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function terminal(): BelongsTo
    {
        return $this->belongsTo(PosTerminal::class, 'pos_terminal_id');
    }

    public function shift(): BelongsTo
    {
        return $this->belongsTo(PosShift::class, 'pos_shift_id');
    }

    public function lines(): HasMany
    {
        return $this->hasMany(PosRefundLine::class, 'pos_refund_id');
    }

    public function tenders(): HasMany
    {
        return $this->hasMany(PosRefundTender::class, 'pos_refund_id');
    }
}

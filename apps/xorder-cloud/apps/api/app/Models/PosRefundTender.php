<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * POS-BE-010: how the money went back. Never a negative `order_payments` row —
 * that column is unsigned on purpose and a refund is not a payment with a
 * minus sign.
 */
class PosRefundTender extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [];

    protected function casts(): array
    {
        return ['amount_minor' => 'integer'];
    }

    public function refund(): BelongsTo
    {
        return $this->belongsTo(PosRefund::class, 'pos_refund_id');
    }

    public function tenderType(): BelongsTo
    {
        return $this->belongsTo(TenderType::class);
    }
}

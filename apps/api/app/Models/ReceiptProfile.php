<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use App\Traits\NormalizesPhoneNumbers;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A3 / CB-08 — who the receipt says sold the food, per branch.
 *
 * One thing wearing two hats, on purpose (the till's own words): the top of a
 * printed slip and the `seller` block of an Egyptian e-receipt are the same
 * facts, and a restaurant asked to type them twice will eventually type them
 * differently. So they are entered once, here, and the till reads them from the
 * bootstrap bundle.
 *
 * The field names lean towards ETA's vocabulary rather than prettier English
 * (`governate` is their spelling) because the one place a mismatch costs real
 * money is the submission.
 *
 * The taxpayer's registration number is NOT here — see the migration.
 */
class ReceiptProfile extends Model
{
    use Auditable, BelongsToRestaurant, NormalizesPhoneNumbers;

    /** Every column the dashboard form authors. `revision` is server-managed. */
    protected $fillable = [
        'trade_name', 'activity_code', 'branch_code',
        'country', 'governate', 'region_city', 'street', 'building_number',
        'postal_code', 'floor', 'room', 'landmark', 'additional_info',
        'phone', 'header_note', 'footer_note',
    ];

    protected function casts(): array
    {
        return ['revision' => 'integer'];
    }

    protected function auditLabel(): string
    {
        return $this->trade_name ?: ('branch #'.$this->branch_id);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}

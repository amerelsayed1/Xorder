<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * CB-09: someone a business buys from.
 *
 * Deliberately carries NO balance. What is owed to a supplier is derived from
 * its invoices and payments (slice c) and never stored. There is no delete: a
 * supplier is retired with is_active = false, because purchase orders,
 * invoices and payments will reference it.
 *
 * `updated_by` is stamped by the controller from the signed-in user and is not
 * fillable, so it can't be forged from a request body.
 */
class Supplier extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = [
        'name_en', 'name_ar', 'code', 'contact_name', 'phone', 'email', 'address',
        'tax_number', 'payment_term_days', 'notes', 'is_active',
    ];

    /** Who last touched it is already the audit actor; not a meaningful diff. */
    protected array $auditExclude = ['updated_by'];

    protected function casts(): array
    {
        return [
            'payment_term_days' => 'integer',
            'is_active' => 'boolean',
        ];
    }

    public function updatedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by');
    }

    protected function auditLabel(): string
    {
        return $this->name_en ?: ($this->name_ar ?: '#'.$this->getKey());
    }
}

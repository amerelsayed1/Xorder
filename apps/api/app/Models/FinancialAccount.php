<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * XORD-015: a place the business keeps money — cash, bank or e-wallet — shared
 * by the whole business (`branch_id` null) or tied to one branch.
 *
 * Never deleted: DELETE deactivates, so anything that later names an account
 * keeps a row to point at. `currency` is set by the server from the
 * restaurant, never from input, so it is not fillable.
 */
class FinancialAccount extends Model
{
    use Auditable, BelongsToRestaurant;

    public const KINDS = ['cash', 'bank', 'wallet'];

    protected $fillable = ['branch_id', 'name', 'kind', 'reference_label', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }
}

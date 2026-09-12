<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * CB-09: a unit a business counts and buys stock in (kg, box, a tray of 30).
 *
 * `code` is immutable once written: later purchasing rows store the code, not
 * the id, so renaming it would silently change what they measured. There is
 * no delete either; a unit is retired with is_active = false. Neither
 * restaurant_id nor code is mass-assignable on update (see UpdateUnitRequest).
 */
class Unit extends Model
{
    use Auditable, BelongsToRestaurant;

    protected $fillable = ['code', 'name_en', 'name_ar', 'eta_unit_type', 'allows_fraction', 'is_active', 'sort_order'];

    protected function casts(): array
    {
        return [
            'allows_fraction' => 'boolean',
            'is_active' => 'boolean',
            'sort_order' => 'integer',
        ];
    }

    protected function auditLabel(): string
    {
        return $this->code ?? '#'.$this->getKey();
    }
}

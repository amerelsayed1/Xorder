<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;

/**
 * A durable dashboard notification. Tenant-scoped via BelongsToRestaurant, so
 * dashboard reads only ever see the signed-in restaurant's feed and public
 * writers (which set restaurant_id explicitly) reach the right tenant even with
 * no resolved TenantContext.
 *
 * Deliberately not Auditable: notifications are system-generated noise and
 * logging their creation would only clutter the audit trail.
 */
class Notification extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'type',
        'title',
        'body',
        'data',
        'read_at',
    ];

    protected function casts(): array
    {
        return [
            'data' => 'array',
            'read_at' => 'datetime',
        ];
    }

    public function isRead(): bool
    {
        return $this->read_at !== null;
    }
}

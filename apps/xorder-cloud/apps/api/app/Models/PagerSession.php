<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * A guest-paging pairing session (docs/features/guest-paging-shared-qr).
 *
 * Deliberately NOT tenant-scoped by a global scope: it is created and read on
 * public requests that have no signed-in tenant, so every query in
 * PagerSessionService names the restaurant explicitly.
 *
 * @property int $id
 * @property int $restaurant_id
 * @property string|null $code
 * @property string $secret_hash
 * @property int|null $order_id
 * @property Carbon $expires_at
 * @property Carbon|null $bound_at
 */
class PagerSession extends Model
{
    protected function casts(): array
    {
        return [
            'expires_at' => 'datetime',
            'bound_at' => 'datetime',
        ];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class)->withoutGlobalScopes();
    }

    public function isBound(): bool
    {
        return $this->bound_at !== null;
    }

    /** Unbound and past its lifetime: the code is dead. */
    public function isExpired(): bool
    {
        return $this->bound_at === null && $this->expires_at->isPast();
    }
}

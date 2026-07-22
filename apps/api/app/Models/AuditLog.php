<?php

namespace App\Models;

use App\Services\AuditLogger;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphTo;

/**
 * An immutable record of something that happened in the system — an admin
 * action, an auth event, a content change, or an order transition. Written by
 * {@see AuditLogger}; never updated after creation.
 */
class AuditLog extends Model
{
    // Audit rows are append-only; there is no meaningful "updated" moment.
    public const UPDATED_AT = null;

    protected $fillable = [
        'restaurant_id',
        'actor_id',
        'actor_name',
        'actor_role',
        'action',
        'auditable_type',
        'auditable_id',
        'description',
        'properties',
        'ip_address',
        'user_agent',
    ];

    protected function casts(): array
    {
        return [
            'properties' => 'array',
        ];
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }

    public function auditable(): MorphTo
    {
        return $this->morphTo();
    }

    /** Coarse category derived from the action key's prefix (auth, restaurant, …). */
    public function getCategoryAttribute(): string
    {
        return str_contains($this->action, '.')
            ? strtok($this->action, '.')
            : $this->action;
    }
}

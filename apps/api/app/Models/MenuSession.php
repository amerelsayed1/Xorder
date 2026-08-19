<?php

namespace App\Models;

use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class MenuSession extends Model
{
    use BelongsToRestaurant;

    /** Presence was established by the branch geofence at scan time. */
    public const PRESENCE_GEOFENCE = 'geofence';

    protected $fillable = [
        'branch_id',
        'dining_area_id',
        'table_id',
        'session_token',
        'language',
        'client_ip',
        'latitude',
        'longitude',
        'accuracy_m',
        'presence_source',
        'on_branch_network',
        'started_at',
        'last_activity_at',
        'expires_at',
        'table_visit_id',
        'closed_at',
    ];

    protected function casts(): array
    {
        return [
            'latitude' => 'float',
            'longitude' => 'float',
            'accuracy_m' => 'integer',
            'on_branch_network' => 'boolean',
            'started_at' => 'datetime',
            'last_activity_at' => 'datetime',
            'expires_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(DiningTable::class, 'table_id');
    }

    public function diningArea(): BelongsTo
    {
        return $this->belongsTo(DiningArea::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function tableVisit(): BelongsTo
    {
        return $this->belongsTo(TableVisit::class);
    }

    public function isExpired(): bool
    {
        return $this->expires_at !== null && $this->expires_at->isPast();
    }

    public function isUsable(): bool
    {
        return $this->closed_at === null && ! $this->isExpired();
    }
}

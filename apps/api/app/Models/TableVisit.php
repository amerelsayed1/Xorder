<?php

namespace App\Models;

use App\Enums\TableVisitStatus;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class TableVisit extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'branch_id', 'dining_area_id', 'table_id', 'status', 'opened_at',
        'closed_at', 'closed_by',
    ];

    protected function casts(): array
    {
        return [
            'status' => TableVisitStatus::class,
            'opened_at' => 'datetime',
            'closed_at' => 'datetime',
        ];
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(DiningTable::class, 'table_id');
    }

    public function sessions(): HasMany
    {
        return $this->hasMany(MenuSession::class);
    }

    public function orders(): HasMany
    {
        return $this->hasMany(Order::class);
    }
}

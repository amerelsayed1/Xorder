<?php

namespace App\Models;

use App\Enums\BillRequestStatus;
use App\Models\Concerns\BelongsToRestaurant;
use App\Traits\NormalizesPhoneNumbers;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

class BillRequest extends Model
{
    use BelongsToRestaurant, NormalizesPhoneNumbers;

    protected $fillable = [
        'branch_id',
        'dining_area_id',
        'table_id',
        'menu_session_id',
        'order_id',
        'public_token',
        'status',
        'customer_note',
        'customer_phone',
        'requested_at',
        'seen_at',
        'started_at',
        'completed_at',
        'cancelled_at',
        'seen_by',
        'completed_by',
    ];

    protected function casts(): array
    {
        return [
            'status' => BillRequestStatus::class,
            'requested_at' => 'datetime',
            'seen_at' => 'datetime',
            'started_at' => 'datetime',
            'completed_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public static function generateToken(): string
    {
        do {
            $token = Str::random(40);
        } while (static::withoutGlobalScopes()->where('public_token', $token)->exists());

        return $token;
    }

    public function isOpen(): bool
    {
        return $this->status->isOpen();
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

    public function menuSession(): BelongsTo
    {
        return $this->belongsTo(MenuSession::class);
    }

    public function order(): BelongsTo
    {
        return $this->belongsTo(Order::class);
    }

    public function seenBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'seen_by');
    }

    public function completedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'completed_by');
    }
}

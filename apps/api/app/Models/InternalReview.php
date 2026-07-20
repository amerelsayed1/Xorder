<?php

namespace App\Models;

use App\Enums\ReviewStatus;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class InternalReview extends Model
{
    use BelongsToRestaurant;

    protected $fillable = [
        'branch_id',
        'dining_area_id',
        'table_id',
        'menu_session_id',
        'order_id',
        'bill_request_id',
        'rating',
        'comment',
        'customer_name',
        'customer_phone',
        'contact_permission',
        'status',
    ];

    protected function casts(): array
    {
        return [
            'status' => ReviewStatus::class,
            'contact_permission' => 'boolean',
            'rating' => 'integer',
        ];
    }

    /** A rating at or below the configured threshold is "low" (needs attention). */
    public function isLow(): bool
    {
        return $this->rating <= (int) config('platform.review_low_rating_threshold', 3);
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

    public function billRequest(): BelongsTo
    {
        return $this->belongsTo(BillRequest::class);
    }

    public function notes(): HasMany
    {
        return $this->hasMany(ReviewInternalNote::class)->latest('id');
    }
}

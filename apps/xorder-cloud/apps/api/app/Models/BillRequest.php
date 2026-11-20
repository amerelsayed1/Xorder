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

    /**
     * Cancel the open "ask for the bill / call the waiter" requests of these
     * tables. Call it before deleting the tables (or an area / branch that
     * cascades to them): the foreign key would otherwise null their `table_id`
     * and leave a card on the live board that points at nothing.
     *
     * It cancels the way the dashboard does when staff cancel one (status,
     * timestamp, unread bell alert marked read). The tenant scope limits it to
     * the caller's own restaurant.
     *
     * @param  array<int,int>  $tableIds
     */
    public static function cancelOpenForTables(array $tableIds): void
    {
        if ($tableIds === []) {
            return;
        }

        $ids = static::query()
            ->whereIn('table_id', $tableIds)
            ->whereIn('status', [
                BillRequestStatus::REQUESTED->value,
                BillRequestStatus::SEEN->value,
                BillRequestStatus::IN_PROGRESS->value,
            ])
            ->pluck('id')->all();

        if ($ids === []) {
            return;
        }

        // Cancel exactly the rows read above, so the alert update below matches them.
        static::query()->whereIn('id', $ids)
            ->update(['status' => BillRequestStatus::CANCELLED->value, 'cancelled_at' => now()]);

        Notification::query()
            ->where('type', 'bill_request.created')
            ->whereIn('data->bill_request_id', array_map('strval', $ids))
            ->whereNull('read_at')
            ->update(['read_at' => now()]);
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

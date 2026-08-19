<?php

namespace App\Models;

use App\Enums\OrderStatus;
use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use App\Traits\NormalizesPhoneNumbers;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Order extends Model
{
    use Auditable, BelongsToRestaurant, NormalizesPhoneNumbers;

    // Orders placed on the public menu have no authenticated user; attribute
    // them to the diner in the audit trail.
    protected function auditActorRoleFallback(): ?string
    {
        return 'CUSTOMER';
    }

    // The order's own labels are its short code, not a name/title column.
    protected function auditLabel(): string
    {
        return $this->code();
    }

    protected $fillable = [
        'status',
        'items',
        'total',
        'currency',
        'customer_id',
        'customer_address_id',
        'customer_name',
        'customer_phone',
        'order_type',
        'note',
        'source',
        'branch_id',
        'dining_area_id',
        'table_id',
        'menu_session_id',
        'table_visit_id',
    ];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            'items' => 'array',
            'total' => 'decimal:2',
        ];
    }

    /** Short human reference the restaurant can read back to the customer. */
    public function code(): string
    {
        return 'ORD-'.$this->id;
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function customerAddress(): BelongsTo
    {
        return $this->belongsTo(CustomerAddress::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function diningArea(): BelongsTo
    {
        return $this->belongsTo(DiningArea::class);
    }

    public function table(): BelongsTo
    {
        return $this->belongsTo(DiningTable::class, 'table_id');
    }

    public function menuSession(): BelongsTo
    {
        return $this->belongsTo(MenuSession::class);
    }

    public function tableVisit(): BelongsTo
    {
        return $this->belongsTo(TableVisit::class);
    }

    public function rounds(): HasMany
    {
        return $this->hasMany(OrderRound::class)->orderBy('sequence');
    }

    public function orderItems(): HasMany
    {
        return $this->hasMany(OrderItem::class);
    }
}

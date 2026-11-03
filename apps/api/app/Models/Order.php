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
            // Stamped by the server on cancellation; never mass-assignable.
            'cancelled_at' => 'datetime',
            'items' => 'array',
            'total' => 'decimal:2',
            // POS columns (Cloud Wave 1) — integer minor units + the client's
            // own event time. All nullable on the QR path.
            'subtotal_minor' => 'integer',
            'discount_minor' => 'integer',
            'tax_minor' => 'integer',
            'charges_minor' => 'integer',
            'total_minor' => 'integer',
            // POS-BE-010: how much of this sale has gone back. A counter, not
            // a SUM — it is what the next refund checks under the order's lock.
            'refunded_minor' => 'integer',
            'received_at' => 'datetime',
            'pos_meta' => 'array',
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

    /** The staff member who cancelled it (null for older or till orders). */
    public function canceller(): BelongsTo
    {
        return $this->belongsTo(User::class, 'cancelled_by');
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

    /** BE-A01: tender rows. Empty for QR orders — no payment is taken there. */
    public function payments(): HasMany
    {
        return $this->hasMany(OrderPayment::class);
    }
}

<?php

namespace App\Models;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
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

    // Guest paging: the tracking token is the diner's only credential and the
    // push token identifies their device — neither belongs in a log line.
    protected array $auditExclude = ['pickup_token', 'pickup_push_token'];

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
        // Guest paging — written by GuestPagingService and the two intake
        // paths (PublicOrderController, PosOrderService), nothing else.
        'pickup_token',
        'pickup_status',
        'pickup_display_ref',
        'pickup_followed_at',
        'ready_at',
        'ready_by',
        'ready_source',
        'acknowledged_at',
        'picked_up_at',
        'pickup_push_token',
    ];

    protected function casts(): array
    {
        return [
            'status' => OrderStatus::class,
            // Stamped by the server on cancellation; never mass-assignable.
            'cancelled_at' => 'datetime',
            'completed_at' => 'datetime',
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
            // Guest paging: a separate lifecycle beside `status` (BR-1).
            'pickup_status' => PickupStatus::class,
            'pickup_followed_at' => 'datetime',
            'ready_at' => 'datetime',
            'acknowledged_at' => 'datetime',
            'picked_up_at' => 'datetime',
        ];
    }

    /** Guest paging: does this order have a tracking token at all? */
    public function isPaged(): bool
    {
        return $this->pickup_token !== null;
    }

    public function readyBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'ready_by');
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

    /** The staff member who completed it (null for older orders and expired visits). */
    public function completer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'completed_by');
    }

    /** POS: the till that rang the sale up (null for QR orders, or once the till is deleted). */
    public function posTerminal(): BelongsTo
    {
        return $this->belongsTo(PosTerminal::class);
    }

    /** POS: the cashier who rang the sale up (null for QR orders). */
    public function actingUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'acting_user_id');
    }

    /**
     * Who handled the order, for the Orders page and its export: whoever
     * closed it out, else the cashier who rang it up. Reads only relations
     * already loaded, so a list never lazy-loads per row.
     */
    public function handledByName(): ?string
    {
        $name = fn (string $rel) => $this->relationLoaded($rel) ? $this->getRelation($rel)?->name : null;

        return match ($this->status) {
            OrderStatus::CANCELLED => $name('canceller'),
            OrderStatus::COMPLETED => $name('completer') ?? $name('actingUser'),
            default => $name('actingUser'),
        };
    }

    /** Whole minutes from placement to completion, or null when not completed. */
    public function minutesToComplete(): ?int
    {
        if ($this->status !== OrderStatus::COMPLETED || $this->completed_at === null || $this->created_at === null) {
            return null;
        }

        return max(0, (int) floor($this->created_at->diffInSeconds($this->completed_at) / 60));
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

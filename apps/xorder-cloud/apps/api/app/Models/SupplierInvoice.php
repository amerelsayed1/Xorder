<?php

namespace App\Models;

use App\Enums\InvoiceVoidReason;
use App\Models\Concerns\BelongsToRestaurant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Query\Builder as QueryBuilder;
use Illuminate\Support\Facades\DB;

/**
 * CB-09 slice c: a bill from a supplier, per branch. The debt.
 *
 * Nothing is mass-assignable. Every write goes through SupplierLedgerService,
 * which locks the invoice row and writes the audit trail itself (created,
 * updated, voided), so the model is deliberately not Auditable.
 *
 * No subtotal and no balance are stored: subtotal = total − tax, and what is
 * paid or outstanding is derived from the live allocations (SupplierAccount).
 * It never touches stock.
 */
class SupplierInvoice extends Model
{
    use BelongsToRestaurant;

    protected $guarded = ['*'];

    protected function casts(): array
    {
        return [
            'branch_id' => 'integer',
            'supplier_id' => 'integer',
            'purchase_order_id' => 'integer',
            'exponent' => 'integer',
            'total_minor' => 'integer',
            'tax_minor' => 'integer',
            'issued_at' => 'date:Y-m-d',
            'due_at' => 'date:Y-m-d',
            'voided_at' => 'datetime',
            'void_reason' => InvoiceVoidReason::class,
        ];
    }

    public function isVoided(): bool
    {
        return $this->voided_at !== null;
    }

    public function lines(): HasMany
    {
        return $this->hasMany(SupplierInvoiceLine::class)->orderBy('sort_order')->orderBy('id');
    }

    public function allocations(): HasMany
    {
        return $this->hasMany(SupplierPaymentAllocation::class);
    }

    public function branch(): BelongsTo
    {
        return $this->belongsTo(Branch::class);
    }

    public function supplier(): BelongsTo
    {
        return $this->belongsTo(Supplier::class);
    }

    public function purchaseOrder(): BelongsTo
    {
        return $this->belongsTo(PurchaseOrder::class);
    }

    /**
     * What the LIVE payments have allocated to this invoice, as a correlated
     * subquery (portable: a join, SUM and COALESCE). Derived on every read;
     * nothing stores it.
     */
    public static function paidSubquery(): QueryBuilder
    {
        return DB::table('supplier_payment_allocations as spa')
            ->join('supplier_payments as sp', 'sp.id', '=', 'spa.supplier_payment_id')
            ->whereColumn('spa.supplier_invoice_id', 'supplier_invoices.id')
            ->whereNull('sp.voided_at')
            ->selectRaw('COALESCE(SUM(spa.amount_minor), 0)');
    }

    /** Adds a derived `paid_minor` to each row. */
    public function scopeWithPaid(Builder $query): Builder
    {
        return $query->select('supplier_invoices.*')->selectSub(self::paidSubquery(), 'paid_minor');
    }

    /** Live and not fully paid; with $overdueBefore, also due before that date. */
    public function scopeOpen(Builder $query, ?string $overdueBefore = null): Builder
    {
        $sub = self::paidSubquery();

        return $query->whereNull('supplier_invoices.voided_at')
            ->whereRaw('supplier_invoices.total_minor > ('.$sub->toSql().')', $sub->getBindings())
            ->when($overdueBefore, fn ($q) => $q->where('supplier_invoices.due_at', '<', $overdueBefore));
    }

    public function scopeSettled(Builder $query): Builder
    {
        $sub = self::paidSubquery();

        return $query->whereNull('supplier_invoices.voided_at')
            ->whereRaw('supplier_invoices.total_minor <= ('.$sub->toSql().')', $sub->getBindings());
    }

    /** The portable stand-in for the till's partial unique index on lower(btrim(number)). */
    public static function numberKey(string $number): string
    {
        return mb_substr(mb_strtolower(trim($number)), 0, 64);
    }
}

<?php

namespace App\Http\Resources;

use App\Models\SupplierInvoice;
use App\Models\SupplierInvoiceLine;
use App\Models\SupplierPaymentAllocation;
use App\Services\PurchaseOrderService;
use App\Support\SupplierAccount;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * CB-09 slice c: a supplier invoice as the dashboard reads it.
 *
 * `paid_minor` comes from SupplierInvoice::scopeWithPaid (the live
 * allocations, derived per read); outstanding, state and lateness are
 * computed here on integers, as at the business's own today.
 *
 * `purchase_order` (when loaded) carries the order's received value and its
 * received total WITH tax (the till's receivedTotal): what an invoice should
 * say. The variance is for comparison only. An invoice never reprices stock.
 *
 * @mixin SupplierInvoice
 */
class SupplierInvoiceResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        /** @var SupplierInvoice $i */
        $i = $this->resource;
        $paid = (int) ($i->getAttribute('paid_minor') ?? 0);
        $asOf = $request->user()?->restaurant?->today() ?? now()->toDateString();
        $due = $i->due_at->format('Y-m-d');
        $voided = $i->isVoided();

        $state = match (true) {
            $voided => 'voided',
            SupplierAccount::isSettled($i->total_minor, $paid) => 'settled',
            SupplierAccount::isOverdue($due, $asOf, false, $i->total_minor, $paid) => 'overdue',
            default => 'open',
        };

        $po = $i->relationLoaded('purchaseOrder') ? $i->purchaseOrder : null;
        $poLines = $po && $po->relationLoaded('lines') ? $po->lines : null;
        $receivedTotal = $poLines !== null ? PurchaseOrderService::receivedTotal($poLines) : null;

        return [
            'id' => $i->id,
            'number' => $i->number,
            'state' => $state,
            'is_voided' => $voided,
            // Its figures are what payments are checked against, so it can
            // change only while nothing is allocated to it.
            'can_edit' => ! $voided && $paid === 0,
            'can_void' => ! $voided && $paid === 0,
            'can_pay' => $state === 'open' || $state === 'overdue',
            'branch_id' => $i->branch_id,
            'branch' => $i->relationLoaded('branch') && $i->branch
                ? ['id' => $i->branch->id, 'name_en' => $i->branch->name_en, 'name_ar' => $i->branch->name_ar]
                : null,
            'supplier_id' => $i->supplier_id,
            'supplier_name' => $i->supplier_name,
            'supplier' => $i->relationLoaded('supplier') && $i->supplier
                ? ['id' => $i->supplier->id, 'name_en' => $i->supplier->name_en, 'name_ar' => $i->supplier->name_ar, 'is_active' => $i->supplier->is_active, 'payment_term_days' => $i->supplier->payment_term_days]
                : null,
            'purchase_order_id' => $i->purchase_order_id,
            'purchase_order_reference' => $i->purchase_order_reference,
            'purchase_order' => $po ? [
                'id' => $po->id,
                'reference' => $po->reference,
                'status' => $po->status->value,
                'closed_short' => $po->isClosedShort(),
                'ordered_total_minor' => $po->total_minor,
                'received_value_minor' => $poLines !== null ? PurchaseOrderService::receivedValue($poLines) : null,
                'received_total_minor' => $receivedTotal,
                'variance_minor' => $receivedTotal !== null ? $i->total_minor - $receivedTotal : null,
            ] : null,
            'currency' => $i->currency,
            'exponent' => $i->exponent,
            'total_minor' => $i->total_minor,
            'tax_minor' => $i->tax_minor,
            'subtotal_minor' => $i->total_minor - $i->tax_minor,
            'paid_minor' => $paid,
            'outstanding_minor' => $voided ? 0 : SupplierAccount::invoiceOutstanding($i->total_minor, $paid),
            'issued_at' => $i->issued_at->format('Y-m-d'),
            'due_at' => $due,
            'days_late' => SupplierAccount::daysLate($due, $asOf, $voided, $i->total_minor, $paid),
            'note' => $i->note,
            'voided_at' => $i->voided_at?->toIso8601String(),
            'void_reason' => $i->void_reason?->value,
            'void_note' => $i->void_note,
            'created_at' => $i->created_at?->toIso8601String(),
            'lines' => $i->relationLoaded('lines') ? $i->lines->map(fn (SupplierInvoiceLine $l) => [
                'id' => $l->id,
                'description' => $l->description,
                'quantity_milli' => $l->quantity_milli,
                'unit_cost_minor' => $l->unit_cost_minor,
                'tax_rate_bp' => $l->tax_rate_bp,
                'line_total_minor' => $l->lineTotalMinor(),
            ])->values()->all() : null,
            'allocations' => $i->relationLoaded('allocations') ? $i->allocations->map(fn (SupplierPaymentAllocation $a) => [
                'id' => $a->id,
                'supplier_payment_id' => $a->supplier_payment_id,
                'amount_minor' => $a->amount_minor,
                'payment' => $a->payment ? [
                    'id' => $a->payment->id,
                    'paid_at' => $a->payment->paid_at->format('Y-m-d'),
                    'method' => $a->payment->method->value,
                    'reference' => $a->payment->reference,
                    'is_voided' => $a->payment->isVoided(),
                ] : null,
            ])->values()->all() : null,
        ];
    }
}

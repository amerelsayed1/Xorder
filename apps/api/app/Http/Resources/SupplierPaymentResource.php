<?php

namespace App\Http\Resources;

use App\Models\SupplierPayment;
use App\Models\SupplierPaymentAllocation;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * CB-09 slice c: a supplier payment as the dashboard reads it.
 *
 * `allocated_minor` is what it put on invoices; `on_account_minor` is the
 * rest. A voided payment keeps its figures for the record, flagged; it no
 * longer counts anywhere (the account and the invoices exclude it).
 *
 * @mixin SupplierPayment
 */
class SupplierPaymentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        /** @var SupplierPayment $p */
        $p = $this->resource;
        $allocated = $p->relationLoaded('allocations')
            ? (int) $p->allocations->sum('amount_minor')
            : (int) ($p->getAttribute('allocations_sum_amount_minor') ?? 0);

        return [
            'id' => $p->id,
            'is_voided' => $p->isVoided(),
            'can_void' => ! $p->isVoided(),
            'branch_id' => $p->branch_id,
            'branch' => $p->relationLoaded('branch') && $p->branch
                ? ['id' => $p->branch->id, 'name_en' => $p->branch->name_en, 'name_ar' => $p->branch->name_ar]
                : null,
            'supplier_id' => $p->supplier_id,
            'supplier_name' => $p->supplier_name,
            'method' => $p->method->value,
            'amount_minor' => $p->amount_minor,
            'allocated_minor' => $allocated,
            'on_account_minor' => $p->amount_minor - $allocated,
            'currency' => $p->currency,
            'exponent' => $p->exponent,
            'reference' => $p->reference,
            'paid_at' => $p->paid_at->format('Y-m-d'),
            'note' => $p->note,
            'pos_cash_movement_id' => $p->pos_cash_movement_id,
            'cash_movement' => $p->relationLoaded('cashMovement') && $p->cashMovement ? [
                'id' => $p->cashMovement->id,
                'amount_minor' => (int) $p->cashMovement->amount_minor,
                'reason' => $p->cashMovement->reason,
                'occurred_at' => $p->cashMovement->occurred_at?->toIso8601String(),
            ] : null,
            'voided_at' => $p->voided_at?->toIso8601String(),
            'void_reason' => $p->void_reason?->value,
            'void_note' => $p->void_note,
            'created_at' => $p->created_at?->toIso8601String(),
            'allocations' => $p->relationLoaded('allocations') ? $p->allocations->map(fn (SupplierPaymentAllocation $a) => [
                'id' => $a->id,
                'supplier_invoice_id' => $a->supplier_invoice_id,
                'amount_minor' => $a->amount_minor,
                'invoice' => $a->relationLoaded('invoice') && $a->invoice ? [
                    'id' => $a->invoice->id,
                    'number' => $a->invoice->number,
                    'total_minor' => $a->invoice->total_minor,
                    'due_at' => $a->invoice->due_at->format('Y-m-d'),
                    'is_voided' => $a->invoice->isVoided(),
                ] : null,
            ])->values()->all() : null,
        ];
    }
}

<?php

namespace App\Http\Resources;

use App\Models\Order;
use App\Services\PosOrderService;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @mixin Order
 */
class OrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'code' => $this->code(),
            'status' => $this->status->value,
            'items' => $this->items,
            'total' => $this->total,
            'currency' => $this->currency,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'customer_id' => $this->customer_id,
            'table_id' => $this->table_id,
            'table_visit_id' => $this->table_visit_id,
            // XORD-048: the table's label, so the list row says "T3" as well.
            'table_label' => $this->whenLoaded('table', fn () => $this->table?->label),
            'rounds' => OrderRoundResource::collection($this->whenLoaded('rounds')),
            'order_type' => $this->order_type,
            'address' => $this->whenLoaded('customerAddress', fn () => $this->customerAddress?->address),
            'note' => $this->note,
            'source' => $this->source,
            'branch' => $this->whenLoaded('branch', fn () => $this->branch ? [
                'id' => $this->branch->id,
                'name_ar' => $this->branch->name_ar,
                'name_en' => $this->branch->name_en,
            ] : null),
            // Till orders only: the derived settlement word the till itself
            // uses (A4). An online order records no payment, so it says null
            // rather than a misleading "unpaid".
            'payment_status' => $this->paymentStatus(),
            'handled_by_name' => $this->resource->handledByName(),
            'completed_at' => $this->completed_at?->toIso8601String(),
            'minutes_to_complete' => $this->resource->minutesToComplete(),
            'cancellation_reason' => $this->cancellation_reason,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancelled_by_name' => $this->whenLoaded('canceller', fn () => $this->canceller?->name),
            // XORD-048: the receipt's facts, on the details request only (it
            // loads `payments`). Stored values, never recomputed; a field the
            // order does not have is null, so a diner order shows no till,
            // cashier or payment.
            $this->mergeWhen($this->resource->relationLoaded('payments'), fn () => [
                'invoice_number' => $this->invoice_number,
                'terminal_name' => $this->posTerminal?->name,
                'cashier_name' => $this->actingUser?->name,
                'dining_area' => $this->diningArea ? [
                    'name_ar' => $this->diningArea->name_ar,
                    'name_en' => $this->diningArea->name_en,
                ] : null,
                'subtotal_minor' => $this->subtotal_minor,
                'discount_minor' => $this->discount_minor,
                'charges_minor' => $this->charges_minor,
                'tax_minor' => $this->tax_minor,
                'total_minor' => $this->total_minor,
                'refunded_minor' => $this->refunded_minor,
                'payments' => $this->payments->map(fn ($p) => [
                    'tender_name' => $p->tenderType?->name,
                    'tender_kind' => $p->tenderType?->kind,
                    'amount_minor' => $p->amount_minor,
                    'received_at' => $p->received_at?->toIso8601String(),
                ])->values(),
            ]),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }

    /** Needs `withSum('payments', 'amount_minor')` on the query; null otherwise. */
    private function paymentStatus(): ?string
    {
        if ($this->source !== 'pos' || ! array_key_exists('payments_sum_amount_minor', $this->resource->getAttributes())) {
            return null;
        }

        return PosOrderService::settlementStatusFrom(
            (int) ($this->total_minor ?? 0),
            (int) ($this->payments_sum_amount_minor ?? 0),
            (int) ($this->refunded_minor ?? 0),
        );
    }
}

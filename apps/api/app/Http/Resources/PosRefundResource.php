<?php

namespace App\Http\Resources;

use App\Enums\CurrencyEnum;
use App\Models\PosRefund;
use App\Services\PosOrderService;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The POS refund wire shape (POS-BE-010). Built ONLY from stored state, so an
 * idempotent replay serialises byte-identically to the first response — credit
 * note number included.
 *
 * `order.settlement_status` is DERIVED on every read (A4). It is the field that
 * carries refund state: the order's own `status` never moves, so REFUNDED and
 * PARTIALLY_REFUNDED are settlement words, not OrderStatus cases.
 *
 * Expects lines, tenders and order to be eager-loaded.
 *
 * @mixin PosRefund
 */
class PosRefundResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $currency = CurrencyEnum::tryFrom((string) $this->currency) ?? CurrencyEnum::EGP;
        $order = $this->order;

        return [
            'id' => $this->id,
            'client_transaction_id' => $this->client_transaction_id,
            'credit_note_number' => $this->credit_note_number,
            'kind' => $this->kind,
            'reason' => $this->reason,
            'order' => [
                'id' => $order?->id,
                'client_transaction_id' => $order?->client_transaction_id,
                'invoice_number' => $order?->invoice_number,
                'total_minor' => (int) ($order?->total_minor ?? 0),
                'refunded_minor' => (int) ($order?->refunded_minor ?? 0),
                'settlement_status' => PosOrderService::settlementStatusFrom(
                    (int) ($order?->total_minor ?? 0),
                    (int) ($order?->payments->sum('amount_minor') ?? 0),
                    (int) ($order?->refunded_minor ?? 0),
                ),
            ],
            'totals' => [
                'total_minor' => (int) $this->total_minor,
                'currency' => $currency->value,
                'exponent' => $currency->exponent(),
            ],
            'lines' => $this->lines->map(fn ($line) => [
                'id' => $line->id,
                'order_item_id' => $line->order_item_id,
                'client_line_id' => $line->orderItem?->client_line_id,
                'name' => $line->name_snapshot,
                'quantity' => $line->quantity,
                'unit_price_minor' => (int) $line->unit_price_minor,
                'amount_minor' => (int) $line->amount_minor,
            ])->values(),
            'tenders' => $this->tenders->map(fn ($tender) => [
                'id' => $tender->id,
                'tender_type_id' => $tender->tender_type_id,
                'amount_minor' => (int) $tender->amount_minor,
            ])->values(),
            'acting_user_id' => $this->acting_user_id,
            'authorized_by_user_id' => $this->authorized_by_user_id,
            'occurred_at' => $this->occurred_at?->toIso8601String(),
            'received_at' => $this->received_at?->toIso8601String(),
        ];
    }
}

<?php

namespace App\Http\Resources;

use App\Enums\CurrencyEnum;
use App\Models\Order;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * The POS order wire shape (POS-BE-006). Built ONLY from stored state, so an
 * idempotent replay serialises byte-identically to the first response —
 * invoice number included. settlement_status is derived (A4), never stored.
 *
 * Expects orderItems and payments to be eager-loaded.
 *
 * @mixin Order
 */
class PosOrderResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $currency = CurrencyEnum::tryFrom((string) $this->currency) ?? CurrencyEnum::EGP;
        $meta = $this->pos_meta ?? [];
        $mismatch = (bool) ($meta['totals_mismatch'] ?? false);

        $paid = (int) $this->payments->sum('amount_minor');
        $total = (int) ($this->total_minor ?? 0);

        $body = [
            'id' => $this->id,
            'client_transaction_id' => $this->client_transaction_id,
            'invoice_number' => $this->invoice_number,
            'status' => $this->status->value,
            'settlement_status' => ($paid >= $total && $total > 0) ? 'PAID' : 'UNPAID',
            'channel' => $this->channel,
            'totals' => [
                'subtotal_minor' => (int) $this->subtotal_minor,
                'discount_minor' => (int) $this->discount_minor,
                'tax_minor' => (int) $this->tax_minor,
                'charges_minor' => (int) $this->charges_minor,
                'total_minor' => $total,
                'currency' => $currency->value,
                'exponent' => $currency->exponent(),
            ],
            'totals_mismatch' => $mismatch,
            'lines' => $this->orderItems->map(fn ($item) => [
                'id' => $item->id,
                'menu_item_id' => $item->menu_item_id,
                'name' => $item->name,
                'quantity' => $item->quantity,
                'options' => $item->options ?? [],
                'note' => $item->note,
                'unit_price_minor' => (int) $item->unit_price_minor,
                'line_total_minor' => (int) $item->line_total_minor,
                'price_source' => $item->price_source,
            ])->values(),
            'payments' => $this->payments->map(fn ($payment) => [
                'id' => $payment->id,
                'client_transaction_id' => $payment->client_transaction_id,
                'tender_type_id' => $payment->tender_type_id,
                'amount_minor' => (int) $payment->amount_minor,
            ])->values(),
            'created_at' => $this->created_at?->toIso8601String(),
            'received_at' => $this->received_at?->toIso8601String(),
        ];

        if ($mismatch) {
            // Both figures, so the till can raise its reconciliation dialog
            // (POS-R081). A mismatch is a marker on a 201, never an error.
            $body['asserted_totals'] = $meta['asserted_totals'] ?? null;
        }

        return $body;
    }
}

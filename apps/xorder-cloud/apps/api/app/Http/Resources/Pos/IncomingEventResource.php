<?php

namespace App\Http\Resources\Pos;

use App\Enums\BillRequestStatus;
use App\Models\BillRequest;
use App\Models\Order;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * POS-BE-033 — one event of `GET /api/pos/incoming`. `$resource` is
 * `['kind' => 'online_order'|'table_request', 'model' => Order|BillRequest]`.
 * Prices are the server's: lines come from the order as the cloud stored them
 * (`price_source: server` once the diner order is server-priced).
 */
class IncomingEventResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return $this->resource['kind'] === 'online_order'
            ? $this->order($this->resource['model'])
            : $this->tableRequest($this->resource['model']);
    }

    /** @return array<string,mixed> */
    private function order(Order $o): array
    {
        $state = $o->rejected_at !== null ? 'rejected' : ($o->accepted_at !== null ? 'accepted' : strtolower($o->status->value));

        return [
            'kind' => 'online_order',
            'id' => $o->id,
            'code' => $o->code(),
            'state' => $state,
            'order_type' => $o->order_type,
            'customer_name' => $o->customer_name,
            'customer_phone' => $o->customer_phone,
            'address' => $o->customerAddress?->address,
            'note' => $o->note,
            'items' => $o->items,
            'total' => $o->total,
            'currency' => $o->currency,
            'placed_at' => $o->created_at?->toIso8601String(),
            'accepted_at' => $o->accepted_at?->toIso8601String(),
            'accepted_by_terminal_id' => $o->accepted_by_terminal_id,
            'rejected_at' => $o->rejected_at?->toIso8601String(),
            'reject_reason' => $o->reject_reason,
            'updated_at' => $o->updated_at?->toIso8601String(),
        ];
    }

    /** @return array<string,mixed> */
    private function tableRequest(BillRequest $r): array
    {
        return [
            'kind' => 'table_request',
            'id' => $r->id,
            'state' => $r->status === BillRequestStatus::COMPLETED ? 'handled'
                : ($r->status === BillRequestStatus::CANCELLED ? 'cancelled' : 'open'),
            'table_id' => $r->table_id,
            'order_id' => $r->order_id,
            'note' => $r->customer_note,
            'requested_at' => $r->requested_at?->toIso8601String(),
            'handled_at' => $r->completed_at?->toIso8601String(),
            'updated_at' => $r->updated_at?->toIso8601String(),
        ];
    }
}

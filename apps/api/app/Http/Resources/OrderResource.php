<?php

namespace App\Http\Resources;

use App\Models\Order;
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
            'rounds' => OrderRoundResource::collection($this->whenLoaded('rounds')),
            'order_type' => $this->order_type,
            'address' => $this->whenLoaded('customerAddress', fn () => $this->customerAddress?->address),
            'note' => $this->note,
            'source' => $this->source,
            // Guest paging (additive). The token is deliberately absent: the
            // dashboard never needs it, and it is the diner's only credential.
            'pickup_status' => $this->pickup_status?->value,
            'pickup_ref' => $this->pickup_display_ref,
            'pickup_followed_at' => $this->pickup_followed_at?->toIso8601String(),
            'ready_at' => $this->ready_at?->toIso8601String(),
            'ready_source' => $this->ready_source,
            'acknowledged_at' => $this->acknowledged_at?->toIso8601String(),
            'picked_up_at' => $this->picked_up_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}

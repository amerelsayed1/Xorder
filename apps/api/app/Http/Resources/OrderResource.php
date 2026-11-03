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
            'cancellation_reason' => $this->cancellation_reason,
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'cancelled_by_name' => $this->whenLoaded('canceller', fn () => $this->canceller?->name),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}

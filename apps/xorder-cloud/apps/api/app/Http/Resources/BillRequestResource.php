<?php

namespace App\Http\Resources;

use App\Models\BillRequest;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin BillRequest */
class BillRequestResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status->value,
            'branch_id' => $this->branch_id,
            'dining_area_id' => $this->dining_area_id,
            'table_id' => $this->table_id,
            'table_label' => $this->table?->label,
            'area_name_en' => $this->whenLoaded('diningArea', fn () => $this->diningArea?->name_en),
            'area_name_ar' => $this->whenLoaded('diningArea', fn () => $this->diningArea?->name_ar),
            'customer_note' => $this->customer_note,
            'customer_phone' => $this->customer_phone,
            'requested_at' => $this->requested_at?->toIso8601String(),
            'seen_at' => $this->seen_at?->toIso8601String(),
            'started_at' => $this->started_at?->toIso8601String(),
            'completed_at' => $this->completed_at?->toIso8601String(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'response_seconds' => ($this->seen_at && $this->requested_at)
                ? (int) abs($this->requested_at->diffInSeconds($this->seen_at))
                : null,
            'elapsed_seconds' => ($this->isOpen() && $this->requested_at)
                ? (int) abs($this->requested_at->diffInSeconds(now()))
                : null,
        ];
    }
}

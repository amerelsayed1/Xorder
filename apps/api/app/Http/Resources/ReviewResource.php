<?php

namespace App\Http\Resources;

use App\Models\InternalReview;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin InternalReview */
class ReviewResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'rating' => $this->rating,
            'comment' => $this->comment,
            'customer_name' => $this->customer_name,
            'customer_phone' => $this->customer_phone,
            'contact_permission' => $this->contact_permission,
            'status' => $this->status->value,
            'branch_id' => $this->branch_id,
            'dining_area_id' => $this->dining_area_id,
            'table_label' => $this->table?->label,
            'area_name_en' => $this->whenLoaded('diningArea', fn () => $this->diningArea?->name_en),
            'area_name_ar' => $this->whenLoaded('diningArea', fn () => $this->diningArea?->name_ar),
            'order_id' => $this->order_id,
            'bill_request_id' => $this->bill_request_id,
            'is_low' => $this->isLow(),
            'created_at' => $this->created_at?->toIso8601String(),
            'notes' => $this->whenLoaded('notes', fn () => $this->notes->map(fn ($n) => [
                'id' => $n->id,
                'note' => $n->note,
                'user_name' => $n->user?->name,
                'created_at' => $n->created_at?->toIso8601String(),
            ])),
        ];
    }
}

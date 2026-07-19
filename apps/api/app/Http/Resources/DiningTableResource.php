<?php

namespace App\Http\Resources;

use App\Models\DiningTable;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin DiningTable */
class DiningTableResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'branch_id' => $this->branch_id,
            'dining_area_id' => $this->dining_area_id,
            'label' => $this->label,
            'seats_count' => $this->seats_count,
            'notes' => $this->notes,
            'public_token' => $this->public_token,
            'is_active' => $this->is_active,
            'qr_generated_at' => $this->qr_generated_at,
            'area_name_en' => $this->whenLoaded('diningArea', fn () => $this->diningArea->name_en),
            'area_name_ar' => $this->whenLoaded('diningArea', fn () => $this->diningArea->name_ar),
        ];
    }
}

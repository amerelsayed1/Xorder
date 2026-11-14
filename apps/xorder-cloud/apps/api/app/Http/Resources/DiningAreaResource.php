<?php

namespace App\Http\Resources;

use App\Models\DiningArea;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin DiningArea */
class DiningAreaResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'branch_id' => $this->branch_id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'type' => $this->type,
            'description' => $this->description,
            'display_order' => $this->display_order,
            'is_active' => $this->is_active,
            'tables_count' => $this->whenCounted('tables'),
        ];
    }
}

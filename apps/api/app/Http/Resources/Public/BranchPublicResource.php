<?php

namespace App\Http\Resources\Public;

use App\Models\Branch;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public branch info shown to guests (branch picker + branches screen).
 *
 * @mixin Branch
 */
class BranchPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'address' => $this->address,
            'phone' => $this->phone,
            'whatsapp_number' => $this->whatsapp_number,
            'opening_hours' => $this->opening_hours,
            'map_url' => $this->map_url,
            'is_open' => $this->is_open,
        ];
    }
}

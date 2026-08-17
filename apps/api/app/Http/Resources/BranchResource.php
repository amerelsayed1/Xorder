<?php

namespace App\Http\Resources;

use App\Models\Branch;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Branch */
class BranchResource extends JsonResource
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
            'business_hours' => (object) ($this->business_hours ?? []),
            'map_url' => $this->map_url,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'geofence' => $this->geofence,
            'geofence_enabled' => (bool) $this->geofence_enabled,
            'require_branch_wifi' => (bool) $this->require_branch_wifi,
            'is_open' => $this->is_open,
            'is_active' => $this->is_active,
            'sort_order' => $this->sort_order,
        ];
    }
}

<?php

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Landing-page lead for the Super Admin lead inbox.
 *
 * @mixin \App\Models\Lead
 */
class LeadResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'restaurant_name' => $this->restaurant_name,
            'contact_name' => $this->contact_name,
            'whatsapp' => $this->whatsapp,
            'city' => $this->city,
            'business_type' => $this->business_type,
            'message' => $this->message,
            'source' => $this->source,
            'status' => $this->status->value,
            'notes' => $this->notes,
            'created_at' => $this->created_at?->toIso8601String(),
        ];
    }
}

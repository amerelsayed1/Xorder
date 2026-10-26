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
            // POS-BE-005: both columns predate this resource and were simply
            // never serialised. `code` doubles as the invoice prefix
            // (POS-BE-008); supported_order_types is [] — never null — so the
            // client can iterate without a null guard.
            'code' => $this->code,
            'supported_order_types' => $this->supported_order_types ?? [],
            // XORD-002: what the subscription lets this branch switch on, so the
            // form offers exactly that. Only the dashboard's own request needs
            // it, and it costs no query when features are already loaded.
            'entitled_order_types' => $this->when(
                $request->user()?->restaurant_id !== null,
                fn () => app(\App\Services\OrderTypeEntitlements::class)->allowed($request->user()->restaurant),
            ),
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

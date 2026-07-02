<?php

namespace App\Http\Resources\Public;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public restaurant header. Deliberately omits status, subscription and other
 * internal fields — only what a diner needs to see.
 *
 * @mixin \App\Models\Restaurant
 */
class RestaurantPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'slug' => $this->slug,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'logo_url' => $this->logo_url,
            'cover_image_url' => $this->cover_image_url,
            'phone' => $this->phone,
            'whatsapp_number' => $this->whatsapp_number,
            'address' => $this->address,
            'opening_hours' => $this->opening_hours,
            'brand_color' => $this->brand_color,
            'secondary_color' => $this->secondary_color,
            'default_language' => $this->default_language->value,
            'bilingual' => $this->bilingual,
            'currency' => $this->currency->value,
            'currency_symbol' => $this->currency->symbol(),
            'ordering_enabled' => $this->ordering_enabled,
        ];
    }
}

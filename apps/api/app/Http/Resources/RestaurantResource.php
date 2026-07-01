<?php

namespace App\Http\Resources;

use App\Enums\RoleEnum;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Full restaurant representation for authenticated dashboards / admin.
 * Public-facing data uses RestaurantPublicResource instead.
 *
 * @mixin \App\Models\Restaurant
 */
class RestaurantResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
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
            'status' => $this->status->value,
            'subscription_status' => $this->subscription_status->value,
            'subscription_plan' => $this->subscription_plan,
            'subscription_start_date' => $this->subscription_start_date?->toDateString(),
            'subscription_end_date' => $this->subscription_end_date?->toDateString(),
            'admin' => $this->whenLoaded('users', function () {
                $admin = $this->users->firstWhere('role', RoleEnum::RESTAURANT_ADMIN);

                return $admin ? [
                    'id' => $admin->id,
                    'name' => $admin->name,
                    'email' => $admin->email,
                    'status' => $admin->status->value,
                ] : null;
            }),
            'public_url' => $this->publicUrl(),
            'categories_count' => $this->whenCounted('categories'),
            'menu_items_count' => $this->whenCounted('menuItems'),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}

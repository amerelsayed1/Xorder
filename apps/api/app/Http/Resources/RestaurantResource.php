<?php

namespace App\Http\Resources;

use App\Enums\RoleEnum;
use App\Models\Restaurant;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Full restaurant representation for authenticated dashboards / admin.
 * Public-facing data uses RestaurantPublicResource instead.
 *
 * @mixin Restaurant
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
            // Always resolved, never null: the settings form needs a concrete
            // zone selected, and callers reading it get the same day boundary
            // the server uses.
            'timezone' => $this->localTimezone(),
            'opening_hours' => $this->opening_hours,
            'business_hours' => (object) ($this->business_hours ?? []),
            'delivery_time_min' => $this->delivery_time_min,
            'delivery_time_max' => $this->delivery_time_max,
            'minimum_order' => $this->minimum_order,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            'social_links' => (object) ($this->social_links ?? []),
            'brand_color' => $this->brand_color,
            'secondary_color' => $this->secondary_color,
            'menu_layout' => $this->menu_layout?->value ?? 'photo',
            'default_language' => $this->default_language->value,
            'bilingual' => $this->bilingual,
            'currency' => $this->currency->value,
            // The owner's ordering switch, and whether the plan entitles any
            // ordering channel — the dashboard hides the switch when it would
            // control nothing.
            'accepts_orders' => (bool) $this->accepts_orders,
            'ordering_entitled' => $this->effectiveOrderingMode() !== null,
            'currency_symbol' => $this->currency->symbol(),
            'ordering_mode' => $this->ordering_mode->value,
            'available_ordering_modes' => array_map(fn ($m) => $m->value, $this->availableOrderingModes()),
            'status' => $this->status->value,
            'subscription_status' => $this->subscription_status->value,
            'subscription_plan' => $this->subscription_plan,
            'subscription_start_date' => $this->subscription_start_date?->toDateString(),
            'subscription_end_date' => $this->subscription_end_date?->toDateString(),
            // Only when eager-loaded. The Super Admin's terminal form needs a
            // branch picker and there is no other admin-side branch read; this
            // avoids inventing one endpoint for one dropdown.
            'branches' => $this->whenLoaded('branches', fn () => $this->branches->map(fn ($branch) => [
                'id' => $branch->id,
                'name_en' => $branch->name_en,
                'name_ar' => $branch->name_ar,
                'code' => $branch->code,
            ])->all()),
            'admin' => $this->whenLoaded('users', function () {
                $admin = $this->users->firstWhere('role', RoleEnum::RESTAURANT_ADMIN);

                return $admin ? [
                    'id' => $admin->id,
                    'name' => $admin->name,
                    'username' => $admin->username,
                    'email' => $admin->email,
                    'status' => $admin->status->value,
                ] : null;
            }),
            'public_url' => $this->publicUrl(),
            'features' => $this->whenLoaded('features', fn () => $this->features
                ->where('is_enabled', true)->pluck('feature_key')->values()),
            'categories_count' => $this->whenCounted('categories'),
            'menu_items_count' => $this->whenCounted('menuItems'),
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}

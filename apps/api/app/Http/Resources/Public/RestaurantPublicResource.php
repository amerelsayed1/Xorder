<?php

namespace App\Http\Resources\Public;

use App\Models\Restaurant;
use App\Support\PublicImageUrl;
use App\Support\SafeUrl;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public restaurant header. Deliberately omits status, subscription and other
 * internal fields — only what a diner needs to see.
 *
 * @mixin Restaurant
 */
class RestaurantPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        // Ordering availability and channel are decided by the plan entitlements
        // (never the raw ordering_mode column), so the menu SPA reflects exactly
        // what the plan grants.
        $mode = $this->effectiveOrderingMode();

        // Working hours now live on the branch. For the menu header/info sheet
        // (a single-restaurant view) source them from the primary active branch
        // when available, falling back to the legacy restaurant-level values.
        $primaryBranch = $this->relationLoaded('branches') ? $this->branches->first() : null;
        $openingHours = $primaryBranch && $primaryBranch->opening_hours !== null
            ? $primaryBranch->opening_hours
            : $this->opening_hours;
        $businessHours = $primaryBranch && ! empty($primaryBranch->business_hours)
            ? $primaryBranch->business_hours
            : $this->business_hours;

        return [
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'slug' => $this->slug,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            // Paths, not absolute URLs: the diner's browser resolves them
            // against {slug}.xorder.io and reuses the connection it already
            // has, instead of opening a second one to the apex that APP_URL
            // baked in at upload time. The cover is the menu's LCP element.
            'logo_url' => PublicImageUrl::relative($this->logo_url),
            'cover_image_url' => PublicImageUrl::relative($this->cover_image_url),
            'phone' => $this->phone,
            'whatsapp_number' => $this->whatsapp_number,
            'address' => $this->address,
            'opening_hours' => $openingHours,
            'business_hours' => (object) ($businessHours ?? []),
            'delivery_time_min' => $this->delivery_time_min,
            'delivery_time_max' => $this->delivery_time_max,
            'minimum_order' => $this->minimum_order,
            'latitude' => $this->latitude,
            'longitude' => $this->longitude,
            // IANA timezone so the menu can decide "open now" in the restaurant's
            // own local time regardless of where the diner is browsing from.
            'timezone' => $this->timezone ?? config('app.timezone'),
            'social_links' => (object) $this->publicSocialLinks(),
            'brand_color' => $this->brand_color,
            'secondary_color' => $this->secondary_color,
            'menu_layout' => $this->menu_layout?->value ?? 'photo',
            'default_language' => $this->default_language->value,
            'bilingual' => $this->bilingual,
            'currency' => $this->currency->value,
            'currency_symbol' => $this->currency->symbol(),
            // Both gates collapse into the one flag the menu SPA already
            // honours: entitled by the plan AND switched on by the owner.
            'ordering_enabled' => $this->acceptsOrdersNow(),
            'ordering_mode' => $mode?->value,
            'order_types' => $this->availableOrderTypes(),
            'internal_reviews' => (bool) $this->hasFeature('internal_reviews'),
            'review_public_url' => SafeUrl::forLink($this->review_public_url),
            'review_thank_you' => app()->getLocale() === 'ar'
                ? ($this->review_thank_you_ar ?: $this->review_thank_you_en)
                : ($this->review_thank_you_en ?: $this->review_thank_you_ar),
        ];
    }
}

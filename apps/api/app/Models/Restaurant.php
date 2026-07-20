<?php

namespace App\Models;

use App\Enums\CurrencyEnum;
use App\Enums\Feature;
use App\Enums\LanguageEnum;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Restaurant extends Model
{
    use HasFactory;

    protected $fillable = [
        'name_ar',
        'name_en',
        'slug',
        'description_ar',
        'description_en',
        'logo_url',
        'cover_image_url',
        'phone',
        'whatsapp_number',
        'address',
        'opening_hours',
        'brand_color',
        'secondary_color',
        'default_language',
        'bilingual',
        'currency',
        'ordering_enabled',
        'status',
        'subscription_status',
        'subscription_plan',
        'subscription_start_date',
        'subscription_end_date',
        'review_public_url',
        'review_thank_you_ar',
        'review_thank_you_en',
    ];

    protected function casts(): array
    {
        return [
            'default_language' => LanguageEnum::class,
            'bilingual' => 'boolean',
            'currency' => CurrencyEnum::class,
            'ordering_enabled' => 'boolean',
            'status' => RestaurantStatus::class,
            'subscription_status' => SubscriptionStatus::class,
            'subscription_start_date' => 'date',
            'subscription_end_date' => 'date',
        ];
    }

    protected function phone(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    protected function whatsappNumber(): Attribute
    {
        return Attribute::make(
            set: fn (?string $value) => $this->normalizePhoneDigits($value),
        );
    }

    private function normalizePhoneDigits(?string $value): ?string
    {
        if (is_null($value)) {
            return null;
        }

        $arabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $englishDigits = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
        $persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

        $value = str_replace($arabicDigits, $englishDigits, $value);

        return str_replace($persianDigits, $englishDigits, $value);
    }

    public function users(): HasMany
    {
        return $this->hasMany(User::class);
    }

    public function categories(): HasMany
    {
        return $this->hasMany(Category::class);
    }

    public function menuItems(): HasMany
    {
        return $this->hasMany(MenuItem::class);
    }

    public function branches(): HasMany
    {
        return $this->hasMany(Branch::class)->orderBy('sort_order')->orderBy('id');
    }

    public function combos(): HasMany
    {
        return $this->hasMany(Combo::class)->orderBy('sort_order')->orderBy('id');
    }

    public function features(): HasMany
    {
        return $this->hasMany(RestaurantFeature::class);
    }

    /**
     * Whether a per-restaurant feature flag is enabled. Reads the loaded
     * relation when present to avoid an extra query in hot paths.
     */
    public function hasFeature(Feature|string $feature): bool
    {
        $key = $feature instanceof Feature ? $feature->value : $feature;

        return (bool) $this->features
            ->firstWhere('feature_key', $key)?->is_enabled;
    }

    /**
     * The public-facing URL the QR code points to.
     *
     * When a menu domain is configured (e.g. tryorder.net) each restaurant is
     * served on its own subdomain: https://{slug}.tryorder.net/menu.
     * Otherwise it falls back to the path-based URL for local/dev.
     */
    public function publicUrl(): string
    {
        $domain = config('platform.menu_domain');

        if ($domain) {
            $scheme = config('platform.menu_secure', true) ? 'https' : 'http';
            $port = config('platform.menu_port');
            $portPart = $port ? ":{$port}" : '';

            return "{$scheme}://{$this->slug}.{$domain}{$portPart}/menu";
        }

        return rtrim(config('app.url'), '/').'/r/'.$this->slug;
    }

    /**
     * The table QR entry point. It lives under the guest menu path (/menu/t/…)
     * because nginx serves the menu SPA there; the app root and other paths on
     * a restaurant subdomain belong to the dashboard SPA.
     */
    public function tableUrl(string $token): string
    {
        $domain = config('platform.menu_domain');

        if ($domain) {
            $scheme = config('platform.menu_secure', true) ? 'https' : 'http';
            $port = config('platform.menu_port');
            $portPart = $port ? ":{$port}" : '';

            return "{$scheme}://{$this->slug}.{$domain}{$portPart}/menu/t/{$token}";
        }

        return rtrim(config('app.url'), '/').'/r/'.$this->slug.'/t/'.$token;
    }

    public function diningAreas(): HasMany
    {
        return $this->hasMany(DiningArea::class);
    }

    public function tables(): HasMany
    {
        return $this->hasMany(DiningTable::class);
    }

    public function isPubliclyVisible(): bool
    {
        return $this->status->isPubliclyVisible();
    }

    /**
     * Order types offered on the public menu, driven by the pickup/delivery
     * feature flags. A restaurant with no feature rows at all (created before
     * the feature system) keeps the legacy default so its menu never silently
     * loses ordering.
     *
     * @return list<string>
     */
    public function availableOrderTypes(): array
    {
        if ($this->features->isEmpty()) {
            return ['pickup', 'delivery'];
        }

        return array_values(array_filter([
            $this->hasFeature(Feature::DINE_IN) ? 'dine_in' : null,
            $this->hasFeature(Feature::PICKUP) ? 'pickup' : null,
            $this->hasFeature(Feature::DELIVERY) ? 'delivery' : null,
        ]));
    }
}

<?php

namespace App\Models;

use App\Enums\LanguageEnum;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
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
        'status',
        'subscription_status',
        'subscription_plan',
        'subscription_start_date',
        'subscription_end_date',
    ];

    protected function casts(): array
    {
        return [
            'default_language' => LanguageEnum::class,
            'status' => RestaurantStatus::class,
            'subscription_status' => SubscriptionStatus::class,
            'subscription_start_date' => 'date',
            'subscription_end_date' => 'date',
        ];
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

        return rtrim(config('app.url'), '/') . '/r/' . $this->slug;
    }

    public function isPubliclyVisible(): bool
    {
        return $this->status->isPubliclyVisible();
    }
}

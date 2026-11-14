<?php

namespace App\Models;

use App\Models\Concerns\Auditable;
use App\Models\Concerns\BelongsToRestaurant;
use App\Support\WeeklyHours;
use Carbon\CarbonInterface;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Category extends Model
{
    use Auditable, BelongsToRestaurant, HasFactory, SoftDeletes;

    protected $fillable = [
        'name_ar',
        'name_en',
        'description_ar',
        'description_en',
        'image_url',
        'display_order',
        'is_active',
        'availability_hours',
    ];

    protected function casts(): array
    {
        return [
            'is_active' => 'boolean',
            'display_order' => 'integer',
            // Per-weekday serving times; null = available whenever the menu is.
            'availability_hours' => 'array',
        ];
    }

    public function menuItems(): HasMany
    {
        return $this->hasMany(MenuItem::class);
    }

    public function restaurant(): BelongsTo
    {
        return $this->belongsTo(Restaurant::class);
    }

    /**
     * Is this category being served at the given moment?
     *
     * Independent of `is_active`, which is the owner switching it off outright.
     * A category can be active and simply out of hours.
     */
    public function isAvailableAt(CarbonInterface $now): bool
    {
        return WeeklyHours::isOpenAt($this->availability_hours, $now);
    }

    /**
     * The same question asked of right now, in the restaurant's own timezone —
     * "before 11am" has to mean 11am where the food is, not on the server.
     */
    public function isAvailableNow(): bool
    {
        return $this->isAvailableAt(now()->setTimezone($this->timezone()));
    }

    /**
     * Today's serving window as ['open' => …, 'close' => …], or null when the
     * category is unrestricted today. Lets the menu say *when* it returns
     * instead of only that it is unavailable.
     *
     * @return array{open: string, close: string}|null
     */
    public function todaysWindow(): ?array
    {
        return WeeklyHours::windowOn($this->availability_hours, now()->setTimezone($this->timezone()));
    }

    /**
     * Falls back to the app timezone rather than lazy-loading the restaurant:
     * the menu payload sets the relation up front, and a query per category
     * here would be an N+1 on every menu view.
     */
    private function timezone(): string
    {
        return ($this->relationLoaded('restaurant') ? $this->restaurant?->timezone : null)
            ?: config('app.timezone', 'UTC');
    }
}

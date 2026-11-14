<?php

use App\Enums\CurrencyEnum;
use App\Models\Restaurant;
use Illuminate\Database\Migrations\Migration;

/**
 * Give every existing restaurant a real timezone.
 *
 * The column has been nullable since it was added, and nothing ever wrote it:
 * no dashboard field offered it and provisioning did not seed it. Null means
 * "fall back to config('app.timezone')", which in production is UTC — so every
 * restaurant's day was turning over at 3am Cairo time. Owners saw the previous
 * day's menu-view count still sitting on the dashboard after midnight.
 *
 * The billing currency is the best signal available for where a restaurant
 * actually is. Currencies that span many zones (USD, EUR, GBP) keep the app
 * default rather than being guessed at. Owners can change the value in their
 * profile afterwards, and that choice is never overwritten by this.
 */
return new class extends Migration
{
    public function up(): void
    {
        $fallback = config('app.timezone', 'UTC');

        Restaurant::withoutGlobalScopes()
            ->whereNull('timezone')
            ->select(['id', 'currency'])
            ->chunkById(200, function ($restaurants) use ($fallback) {
                foreach ($restaurants as $restaurant) {
                    $currency = $restaurant->currency instanceof CurrencyEnum
                        ? $restaurant->currency
                        : CurrencyEnum::tryFrom((string) $restaurant->currency);

                    Restaurant::withoutGlobalScopes()
                        ->whereKey($restaurant->id)
                        ->update(['timezone' => $currency?->defaultTimezone() ?: $fallback]);
                }
            });
    }

    /**
     * Deliberately irreversible in data terms: rolling back would have to guess
     * which values were backfilled and which an owner chose, and blanking an
     * owner's deliberate setting is worse than leaving a correct one in place.
     * The column stays nullable, so nothing structural needs undoing.
     */
    public function down(): void {}
};

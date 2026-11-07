<?php

namespace App\Services;

use App\Models\Branch;
use App\Models\Charge;
use App\Models\FinancialAccount;
use App\Models\PosTerminal;
use App\Models\ReceiptProfile;
use App\Models\Restaurant;
use App\Models\TaxRule;
use App\Models\TenderAccountDefault;
use App\Models\TenderType;
use Illuminate\Database\Eloquent\Model;

/**
 * The ONE place restaurants.pos_config_version moves (POS-BE-025).
 *
 * The version is the client's sole precedence signal: a till accepts a bundle
 * iff incoming > cached, and treats a lower value as a rollback to refuse. So
 * it is monotonic, never reused, never reset — an atomic SQL increment, not a
 * read-modify-write.
 *
 * Coverage: rather than sprinkling bump() through every controller that can
 * change the bundle, the bundle-shaped models are hooked once here (called
 * from AppServiceProvider::boot). Branch, TaxRule, Charge, TenderType,
 * PosTerminal and ReceiptProfile writes bump automatically; the PIN endpoints
 * and the restaurant's tax registration number bump explicitly (User and
 * Restaurant writes are far too broad to hook — a password change or a new
 * cover image is not a bundle change).
 *
 * The restaurant's two BRANDING fields that the bundle carries (`logo_url`,
 * `brand_color`) bump too, through a narrow `updated` hook on Restaurant that
 * fires only when one of them actually changed (XORD-021): a till only re-reads
 * the bundle when this number moves, so without it a new logo would reach the
 * tills whenever something unrelated happened to bump. Nothing else on the
 * restaurant row does.
 *
 * KNOWN GAP (recorded in the wave journal): staff role changes and the rest of
 * the restaurant profile (currency) do not bump yet. The heartbeat's
 * config_version still refreshes tills periodically, so the effect is a
 * delayed pickup, not a wrong bundle.
 */
class PosConfigVersion
{
    public static function bump(Restaurant|int|null $restaurant): void
    {
        $id = $restaurant instanceof Restaurant ? $restaurant->id : $restaurant;

        if ($id === null) {
            return;
        }

        Restaurant::whereKey($id)->increment('pos_config_version');
    }

    /** Wire the model events. Called once from AppServiceProvider::boot(). */
    public static function registerHooks(): void
    {
        $bump = function (Model $model): void {
            self::bump($model->restaurant_id ?? null);
        };

        foreach ([Branch::class, TaxRule::class, Charge::class, TenderType::class, FinancialAccount::class, TenderAccountDefault::class, PosTerminal::class, ReceiptProfile::class] as $class) {
            $class::saved($bump);
            $class::deleted($bump);
        }

        // Only the two branding fields the bundle's `branding` block carries.
        // `wasChanged`, not `isDirty`: this runs after the save, and a profile
        // form that posts the same logo back changes nothing and bumps nothing.
        Restaurant::updated(function (Restaurant $restaurant): void {
            if ($restaurant->wasChanged(['logo_url', 'brand_color'])) {
                self::bump($restaurant);
            }
        });
    }

    public static function current(Restaurant|int $restaurant): int
    {
        if ($restaurant instanceof Restaurant) {
            return (int) $restaurant->pos_config_version;
        }

        return (int) Restaurant::whereKey($restaurant)->value('pos_config_version');
    }
}

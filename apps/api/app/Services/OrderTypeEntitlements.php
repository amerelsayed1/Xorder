<?php

namespace App\Services;

use App\Enums\Feature;
use App\Models\Restaurant;

/**
 * Which order types a restaurant may offer (XORD-002), and the one spelling they
 * are stored in.
 *
 * **Vocabulary.** The till knows four: dine_in, takeaway, delivery, drive_thru.
 * The Super Admin wizard writes `pickup` for takeaway because it mirrors the
 * plan's feature keys, and the branch form has accepted both. Everything this
 * class returns is the till's spelling, so a list is comparable whichever way
 * it was written; `PosOrderService` already treats the two as one.
 *
 * **Entitlement is the subscription's feature flags**, nothing new:
 * dine_in ← `dine_in`, takeaway ← `pickup`, delivery ← `delivery`. Drive-thru
 * has no flag of its own because a drive-thru lane only exists at a till, so it
 * follows `pos`. That last mapping is a decision, not a fact from the plans:
 * it is recorded in docs and open to the owner.
 *
 * This answers "may it be ENABLED". It is applied when a list is written; it is
 * deliberately not applied when an order arrives, because a tenant whose flag
 * rows were never set would then be refused sales it has always taken.
 */
final class OrderTypeEntitlements
{
    /** The till's order types, in the order it shows them. */
    public const TYPES = ['dine_in', 'takeaway', 'delivery', 'drive_thru'];

    private const FLAG = [
        'dine_in' => Feature::DINE_IN,
        'takeaway' => Feature::PICKUP,
        'delivery' => Feature::DELIVERY,
        'drive_thru' => Feature::POS,
    ];

    /** The till's spelling of one value; unknown values come back unchanged. */
    public static function canonical(string $value): string
    {
        return $value === 'pickup' ? 'takeaway' : $value;
    }

    /**
     * A list in the till's spelling, without repeats, in the till's order.
     * Values it does not know are kept after the known ones, so a list is never
     * silently shortened by a spelling this class has not heard of.
     *
     * @param  array<int, mixed>  $values
     * @return list<string>
     */
    public static function normalise(array $values): array
    {
        $seen = [];
        foreach ($values as $value) {
            if (is_string($value) && $value !== '') {
                $seen[self::canonical($value)] = true;
            }
        }

        $known = array_values(array_filter(self::TYPES, fn ($type) => isset($seen[$type])));
        $other = array_values(array_diff(array_keys($seen), self::TYPES));

        return [...$known, ...$other];
    }

    /**
     * The order types this restaurant's subscription lets it enable.
     *
     * @return list<string>
     */
    public function allowed(Restaurant $restaurant): array
    {
        // Strict models forbid lazy loading outside production; load once here.
        $restaurant->loadMissing('features');

        return array_values(array_filter(
            self::TYPES,
            fn (string $type) => $restaurant->hasFeature(self::FLAG[$type]),
        ));
    }
}

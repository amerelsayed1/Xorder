<?php

namespace App\Services;

use App\Models\Unit;
use Illuminate\Database\UniqueConstraintViolationException;

/**
 * CB-09: the seven units every business starts with, copied verbatim from the
 * till's pos_seed_units (xorder-pos migration 39), EN and AR names included,
 * so a unit code means the same thing on both sides.
 *
 * Created lazily, on the first units read of a tenant that has purchasing,
 * rather than by a migration: seeding every existing tenant would write rows
 * for businesses that never bought the feature.
 *
 * Idempotent because units are never deleted: a default that is missing was
 * never created, so creating it is always right, and one that exists (even
 * retired, or added by hand first) is left exactly as it is. Two concurrent
 * first reads race on unique(restaurant_id, code) and the loser just moves on.
 */
class UnitCatalog
{
    /** @var list<array{code:string,name_en:string,name_ar:string,eta_unit_type:string,allows_fraction:bool,sort_order:int}> */
    public const DEFAULTS = [
        ['code' => 'ea', 'name_en' => 'Each', 'name_ar' => 'قطعة', 'eta_unit_type' => 'EA', 'allows_fraction' => false, 'sort_order' => 10],
        ['code' => 'kg', 'name_en' => 'Kilogram', 'name_ar' => 'كيلوجرام', 'eta_unit_type' => 'KGM', 'allows_fraction' => true, 'sort_order' => 20],
        ['code' => 'g', 'name_en' => 'Gram', 'name_ar' => 'جرام', 'eta_unit_type' => 'GRM', 'allows_fraction' => true, 'sort_order' => 30],
        ['code' => 'l', 'name_en' => 'Litre', 'name_ar' => 'لتر', 'eta_unit_type' => 'LTR', 'allows_fraction' => true, 'sort_order' => 40],
        ['code' => 'ml', 'name_en' => 'Millilitre', 'name_ar' => 'مليلتر', 'eta_unit_type' => 'MLT', 'allows_fraction' => true, 'sort_order' => 50],
        ['code' => 'box', 'name_en' => 'Box', 'name_ar' => 'علبة', 'eta_unit_type' => 'BX', 'allows_fraction' => false, 'sort_order' => 60],
        ['code' => 'pack', 'name_en' => 'Pack', 'name_ar' => 'عبوة', 'eta_unit_type' => 'PK', 'allows_fraction' => false, 'sort_order' => 70],
    ];

    public function ensureDefaults(int $restaurantId): void
    {
        $existing = Unit::withoutGlobalScopes()
            ->where('restaurant_id', $restaurantId)
            ->pluck('code')
            ->all();

        $missing = array_filter(self::DEFAULTS, fn (array $d) => ! in_array($d['code'], $existing, true));

        if ($missing === []) {
            return;
        }

        // Seeding is the system's doing, not the person who happened to open
        // the page, so it doesn't write seven audit entries in their name.
        Unit::withoutEvents(function () use ($missing, $restaurantId) {
            foreach ($missing as $default) {
                try {
                    (new Unit)->forceFill($default + ['restaurant_id' => $restaurantId, 'is_active' => true])->save();
                } catch (UniqueConstraintViolationException) {
                    // A concurrent first read created it. Nothing to do.
                }
            }
        });
    }
}

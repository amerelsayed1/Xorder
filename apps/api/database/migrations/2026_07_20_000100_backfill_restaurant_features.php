<?php

use App\Enums\Feature;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    /**
     * Restaurants created before the feature-flag system have no rows in
     * restaurant_features, which would make the public menu read them as
     * "everything disabled" (e.g. no order types). Seed the default set for
     * any such restaurant so existing menus keep behaving as before.
     */
    public function up(): void
    {
        $now = now();
        $defaults = Feature::defaultSet();

        DB::table('restaurants')
            ->whereNotExists(function ($q) {
                $q->select(DB::raw(1))
                    ->from('restaurant_features')
                    ->whereColumn('restaurant_features.restaurant_id', 'restaurants.id');
            })
            ->orderBy('id')
            ->pluck('id')
            ->each(function ($restaurantId) use ($defaults, $now) {
                $rows = [];
                foreach ($defaults as $key => $enabled) {
                    $rows[] = [
                        'restaurant_id' => $restaurantId,
                        'feature_key' => $key,
                        'is_enabled' => $enabled,
                        'enabled_at' => $enabled ? $now : null,
                        'enabled_by' => null,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ];
                }
                DB::table('restaurant_features')->insert($rows);
            });
    }

    public function down(): void
    {
        // One-way backfill; leaving the rows in place is harmless.
    }
};

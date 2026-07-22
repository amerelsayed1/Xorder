<?php

namespace App\Console\Commands;

use App\Models\Restaurant;
use App\Services\PlanEntitlementService;
use Illuminate\Console\Command;

/**
 * Re-derive each restaurant's feature flags from its subscription plan, fixing
 * any entitlement drift (e.g. a plan whose feature_keys were narrowed after
 * clients were already provisioned). Idempotent and safe to re-run.
 */
class SyncRestaurantEntitlements extends Command
{
    protected $signature = 'restaurants:sync-entitlements
        {--restaurant= : Sync only this restaurant id}';

    protected $description = "Re-derive restaurants' feature flags from their plans (fixes entitlement drift)";

    public function handle(PlanEntitlementService $entitlements): int
    {
        $synced = 0;
        $skipped = 0;

        Restaurant::query()
            ->when($this->option('restaurant'), fn ($q) => $q->whereKey($this->option('restaurant')))
            ->chunkById(100, function ($restaurants) use ($entitlements, &$synced, &$skipped) {
                foreach ($restaurants as $restaurant) {
                    // sync() is a no-op when the plan is unknown or predates the
                    // entitlement set, leaving those tenants untouched.
                    $before = $restaurant->features()->where('is_enabled', true)->count();
                    $entitlements->sync($restaurant);
                    $after = $restaurant->features()->where('is_enabled', true)->count();

                    $plan = $restaurant->subscription_plan ?: '—';
                    $this->line("  #{$restaurant->id} {$restaurant->slug} [{$plan}]: {$before} → {$after} features");
                    $synced++;
                }
            });

        $this->info("Processed {$synced} restaurant(s).");

        return self::SUCCESS;
    }
}

<?php

namespace App\Console\Commands;

use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use App\Notifications\SubscriptionExpiringSoon;
use Illuminate\Console\Command;

class ProcessSubscriptionsCommand extends Command
{
    protected $signature = 'subscriptions:process';

    protected $description = 'Expire ended subscriptions and warn admins 7 days (and 1 day) before expiry';

    public function handle(): int
    {
        $expired = Restaurant::query()
            ->whereIn('subscription_status', [SubscriptionStatus::TRIAL, SubscriptionStatus::ACTIVE])
            ->whereNotNull('subscription_end_date')
            ->whereDate('subscription_end_date', '<', now()->toDateString())
            ->get();

        foreach ($expired as $restaurant) {
            $restaurant->update(['subscription_status' => SubscriptionStatus::EXPIRED]);
            $this->info("Expired: {$restaurant->slug}");
        }

        // Warn exactly at 7 and 1 day(s) out — the daily schedule makes each
        // threshold fire once, so no "already warned" bookkeeping is needed.
        foreach ([7, 1] as $days) {
            $ending = Restaurant::query()
                ->whereIn('subscription_status', [SubscriptionStatus::TRIAL, SubscriptionStatus::ACTIVE])
                ->whereDate('subscription_end_date', now()->addDays($days)->toDateString())
                ->with('users')
                ->get();

            foreach ($ending as $restaurant) {
                foreach ($restaurant->users as $admin) {
                    $admin->notify(new SubscriptionExpiringSoon($restaurant, $days));
                }
                $this->info("Warned ({$days}d): {$restaurant->slug}");
            }
        }

        $this->info("Done. {$expired->count()} expired.");

        return self::SUCCESS;
    }
}

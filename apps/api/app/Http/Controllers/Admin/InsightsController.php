<?php

namespace App\Http\Controllers\Admin;

use App\Enums\RestaurantStatus;
use App\Enums\RoleEnum;
use App\Enums\SubscriptionStatus;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Carbon;

/**
 * Platform-wide insights for the Super Admin.
 *
 * This is a menu-only MVP (no orders / payments), so the meaningful signals
 * are tenant growth, subscription lifecycle, content footprint, and which
 * restaurants need a nudge (empty menus, lapsing subscriptions).
 *
 * Queries here are NOT tenant-scoped: the Super Admin has no tenant context,
 * so the global RestaurantScope is a no-op and these counts span all tenants.
 */
class InsightsController extends Controller
{
    public function index(): JsonResponse
    {
        $now = Carbon::now();
        $soon = $now->copy()->addDays(7);
        $month = $now->copy()->addDays(30);

        $restaurantsByStatus = $this->countByEnum(
            Restaurant::query()->selectRaw('status, count(*) as aggregate')->groupBy('status')->pluck('aggregate', 'status'),
            RestaurantStatus::cases(),
        );

        $subscriptionsByStatus = $this->countByEnum(
            Restaurant::query()->selectRaw('subscription_status, count(*) as aggregate')->groupBy('subscription_status')->pluck('aggregate', 'subscription_status'),
            SubscriptionStatus::cases(),
        );

        $activeSubStates = [SubscriptionStatus::TRIAL->value, SubscriptionStatus::ACTIVE->value];

        $expiringSoon = Restaurant::query()
            ->whereIn('subscription_status', $activeSubStates)
            ->whereNotNull('subscription_end_date')
            ->whereBetween('subscription_end_date', [$now->toDateString(), $soon->toDateString()])
            ->count();

        $expiringThisMonth = Restaurant::query()
            ->whereIn('subscription_status', $activeSubStates)
            ->whereNotNull('subscription_end_date')
            ->whereBetween('subscription_end_date', [$now->toDateString(), $month->toDateString()])
            ->count();

        $lapsed = Restaurant::query()
            ->whereIn('subscription_status', $activeSubStates)
            ->whereNotNull('subscription_end_date')
            ->whereDate('subscription_end_date', '<', $now->toDateString())
            ->count();

        return response()->json([
            'data' => [
                'restaurants' => [
                    'total' => array_sum($restaurantsByStatus),
                    'by_status' => $restaurantsByStatus,
                    'new_last_7_days' => Restaurant::where('created_at', '>=', $now->copy()->subDays(7))->count(),
                    'new_last_30_days' => Restaurant::where('created_at', '>=', $now->copy()->subDays(30))->count(),
                ],
                'subscriptions' => [
                    'by_status' => $subscriptionsByStatus,
                    'expiring_in_7_days' => $expiringSoon,
                    'expiring_in_30_days' => $expiringThisMonth,
                    'past_end_date' => $lapsed,
                ],
                'content' => [
                    'total_categories' => Category::count(),
                    'total_menu_items' => MenuItem::count(),
                    'available_menu_items' => MenuItem::where('is_available', true)->count(),
                    'restaurant_admins' => User::where('role', RoleEnum::RESTAURANT_ADMIN)->count(),
                ],
                'needs_attention' => [
                    'restaurants_without_menu_items' => Restaurant::doesntHave('menuItems')->count(),
                    'restaurants_without_categories' => Restaurant::doesntHave('categories')->count(),
                    'subscriptions_expiring_in_7_days' => $expiringSoon,
                    'subscriptions_past_end_date' => $lapsed,
                ],
                'top_restaurants' => Restaurant::query()
                    ->withCount(['menuItems', 'categories'])
                    ->orderByDesc('menu_items_count')
                    ->take(5)
                    ->get()
                    ->map(fn (Restaurant $r) => [
                        'id' => $r->id,
                        'name' => $r->name_en ?: $r->name_ar,
                        'slug' => $r->slug,
                        'status' => $r->status->value,
                        'menu_items_count' => $r->menu_items_count,
                        'categories_count' => $r->categories_count,
                    ]),
                'recent_restaurants' => Restaurant::query()
                    ->latest()
                    ->take(5)
                    ->get()
                    ->map(fn (Restaurant $r) => [
                        'id' => $r->id,
                        'name' => $r->name_en ?: $r->name_ar,
                        'slug' => $r->slug,
                        'status' => $r->status->value,
                        'subscription_status' => $r->subscription_status->value,
                        'created_at' => $r->created_at?->toIso8601String(),
                    ]),
            ],
        ]);
    }

    /**
     * Normalise a grouped count keyed by enum value, ensuring every case is
     * present (zero-filled) regardless of whether rows exist for it.
     *
     * @param  \Illuminate\Support\Collection<string, int>  $counts
     * @param  array<int, \BackedEnum>  $cases
     * @return array<string, int>
     */
    private function countByEnum($counts, array $cases): array
    {
        $result = [];
        foreach ($cases as $case) {
            $result[$case->value] = (int) ($counts[$case->value] ?? 0);
        }

        return $result;
    }
}

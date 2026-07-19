<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\MenuViewDaily;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Actionable "menu-health" insights for a Restaurant Admin.
 *
 * No orders/analytics exist in the MVP, so the most useful things we can
 * surface are the gaps that hurt the public menu: empty categories (hidden
 * from customers), items missing photos/translations/descriptions, and the
 * subscription clock. Every query is tenant-scoped automatically by the
 * global RestaurantScope.
 */
class InsightsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        $totalItems = MenuItem::count();
        $availableItems = MenuItem::where('is_available', true)->count();
        $featuredItems = MenuItem::where('is_featured', true)->count();
        $discountedItems = MenuItem::whereNotNull('discounted_price')->count();

        $totalCategories = Category::count();
        $activeCategories = Category::where('is_active', true)->count();

        // Active categories with zero items are invisible on the public menu.
        $emptyActiveCategories = Category::where('is_active', true)
            ->doesntHave('menuItems')
            ->orderBy('display_order')
            ->get(['id', 'name_en', 'name_ar']);

        // Content gaps that weaken the published menu.
        $itemsMissingImage = MenuItem::whereNull('image_url')->count();
        $itemsMissingDescription = MenuItem::whereNull('description_en')
            ->whereNull('description_ar')
            ->count();
        $itemsMissingTranslation = MenuItem::where(function ($q) {
            $q->whereNull('name_en')->orWhere('name_en', '')
                ->orWhereNull('name_ar')->orWhere('name_ar', '');
        })->count();

        $pricing = MenuItem::selectRaw('avg(price) as avg_price, min(price) as min_price, max(price) as max_price')
            ->where('price', '>', 0)
            ->first();

        // Largest categories give a quick sense of where the menu is concentrated.
        $categoryBreakdown = Category::withCount('menuItems')
            ->orderByDesc('menu_items_count')
            ->take(5)
            ->get()
            ->map(fn (Category $c) => [
                'id' => $c->id,
                'name' => $c->name_en ?: $c->name_ar,
                'is_active' => $c->is_active,
                'menu_items_count' => $c->menu_items_count,
            ]);

        $endDate = $restaurant->subscription_end_date;
        $daysRemaining = $endDate
            ? Carbon::now()->startOfDay()->diffInDays($endDate->copy()->startOfDay(), false)
            : null;

        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'is_public' => $restaurant->isPubliclyVisible(),
                'subscription' => [
                    'status' => $restaurant->subscription_status->value,
                    'plan' => $restaurant->subscription_plan,
                    'end_date' => $endDate?->toDateString(),
                    'days_remaining' => $daysRemaining !== null ? (int) $daysRemaining : null,
                    'writable' => $restaurant->subscription_status->allowsDashboardWrites(),
                ],
                'menu' => [
                    'total_items' => $totalItems,
                    'available_items' => $availableItems,
                    'unavailable_items' => $totalItems - $availableItems,
                    'featured_items' => $featuredItems,
                    'discounted_items' => $discountedItems,
                    'total_categories' => $totalCategories,
                    'active_categories' => $activeCategories,
                    'inactive_categories' => $totalCategories - $activeCategories,
                ],
                'pricing' => [
                    'average_price' => $pricing?->avg_price !== null ? round((float) $pricing->avg_price, 2) : null,
                    'min_price' => $pricing?->min_price !== null ? (float) $pricing->min_price : null,
                    'max_price' => $pricing?->max_price !== null ? (float) $pricing->max_price : null,
                ],
                'engagement' => $this->engagement(),
                'top_items' => $this->topItems(),
                'category_breakdown' => $categoryBreakdown,
                'needs_attention' => $this->needsAttention(
                    emptyActiveCategories: $emptyActiveCategories,
                    unavailableItems: $totalItems - $availableItems,
                    itemsMissingImage: $itemsMissingImage,
                    itemsMissingTranslation: $itemsMissingTranslation,
                    itemsMissingDescription: $itemsMissingDescription,
                    totalItems: $totalItems,
                ),
            ],
        ]);
    }

    /**
     * Menu views + orders — the numbers that show owners the QR menu is
     * working for them. Queries are tenant-scoped by the global scope.
     *
     * @return array<string, mixed>
     */
    private function engagement(): array
    {
        $today = now()->toDateString();
        $since = now()->subDays(13)->toDateString();

        $viewRows = MenuViewDaily::whereDate('date', '>=', $since)
            ->orderBy('date')
            ->get(['date', 'views'])
            ->keyBy(fn (MenuViewDaily $row) => $row->date->toDateString());

        $orderRows = Order::where('created_at', '>=', now()->subDays(13)->startOfDay())
            ->selectRaw('date(created_at) as day, count(*) as total')
            ->groupBy('day')
            ->pluck('total', 'day');

        // Dense 14-day series so charts don't have holes on quiet days.
        $series = collect(range(13, 0))->map(function (int $daysAgo) use ($viewRows, $orderRows) {
            $day = now()->subDays($daysAgo)->toDateString();

            return [
                'date' => $day,
                'views' => (int) ($viewRows[$day]->views ?? 0),
                'orders' => (int) ($orderRows[$day] ?? 0),
            ];
        })->values();

        return [
            'views_today' => (int) ($viewRows[$today]->views ?? 0),
            'views_14d' => (int) $viewRows->sum('views'),
            'orders_total' => Order::count(),
            'orders_new' => Order::where('status', OrderStatus::NEW)->count(),
            'orders_14d' => (int) $orderRows->sum(),
            'daily' => $series,
        ];
    }

    /**
     * Most-ordered menu items, aggregated from the order snapshots (orders
     * store their line items as JSON). Cancelled orders don't count. Returns
     * [{ name, qty }] sorted by total quantity, top $limit.
     *
     * @return array<int, array{name: string, qty: int}>
     */
    private function topItems(int $limit = 8): array
    {
        $counts = [];

        Order::where('status', '!=', OrderStatus::CANCELLED->value)
            ->select('items')
            ->chunk(500, function ($orders) use (&$counts) {
                foreach ($orders as $order) {
                    foreach (($order->items ?? []) as $line) {
                        $name = trim((string) ($line['name'] ?? ''));
                        if ($name === '') {
                            continue;
                        }
                        $counts[$name] = ($counts[$name] ?? 0) + max(1, (int) ($line['qty'] ?? 1));
                    }
                }
            });

        arsort($counts);

        return collect($counts)
            ->take($limit)
            ->map(fn (int $qty, string $name) => ['name' => $name, 'qty' => $qty])
            ->values()
            ->all();
    }

    /**
     * Build a prioritised, frontend-friendly list of actionable issues.
     * Each entry: { key, count, severity, sample? }. Items with count 0 are
     * dropped so the UI only shows real to-dos.
     *
     * @param  Collection  $emptyActiveCategories
     * @return array<int, array<string, mixed>>
     */
    private function needsAttention(
        $emptyActiveCategories,
        int $unavailableItems,
        int $itemsMissingImage,
        int $itemsMissingTranslation,
        int $itemsMissingDescription,
        int $totalItems,
    ): array {
        $issues = [];

        if ($totalItems === 0) {
            $issues[] = ['key' => 'no_items', 'count' => 1, 'severity' => 'high'];
        }

        if ($emptyActiveCategories->isNotEmpty()) {
            $issues[] = [
                'key' => 'empty_active_categories',
                'count' => $emptyActiveCategories->count(),
                'severity' => 'high',
                'sample' => $emptyActiveCategories
                    ->take(5)
                    ->map(fn ($c) => $c->name_en ?: $c->name_ar)
                    ->values(),
            ];
        }

        $candidates = [
            ['key' => 'items_missing_image', 'count' => $itemsMissingImage, 'severity' => 'medium'],
            ['key' => 'items_missing_translation', 'count' => $itemsMissingTranslation, 'severity' => 'medium'],
            ['key' => 'items_missing_description', 'count' => $itemsMissingDescription, 'severity' => 'low'],
            ['key' => 'unavailable_items', 'count' => $unavailableItems, 'severity' => 'low'],
        ];

        foreach ($candidates as $candidate) {
            if ($candidate['count'] > 0) {
                $issues[] = $candidate;
            }
        }

        return $issues;
    }
}

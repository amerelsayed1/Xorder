<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Models\Category;
use App\Models\MenuItem;
use App\Models\MenuViewDaily;
use App\Models\Order;
use App\Models\OrderPayment;
use App\Models\PosShift;
use App\Models\Restaurant;
use App\Services\PosShiftService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

class StatsController extends Controller
{
    public function __construct(private readonly PosShiftService $shifts) {}

    /** Dashboard-home counters. Queries are tenant-scoped automatically. */
    public function index(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        $totalItems = MenuItem::count();

        // "Available" means available to a diner, which an item in a switched-off
        // category is not — the public menu only loads active categories, so
        // counting those items here reported stock the menu never shows. The
        // difference lands in unavailable_items below, where it belongs: they
        // are items the owner still has, just not ones anyone can order.
        $availableItems = MenuItem::where('is_available', true)
            ->whereHas('category', fn ($q) => $q->where('is_active', true))
            ->count();

        [$salesToday, $ordersToday] = $this->salesFor($restaurant, 0);
        [$salesYesterday] = $this->salesFor($restaurant, 1);

        $viewsToday = (int) MenuViewDaily::whereDate('date', $restaurant->today())->sum('views');
        $viewsYesterday = (int) MenuViewDaily::whereDate(
            'date',
            Carbon::now($restaurant->localTimezone())->subDay()->toDateString(),
        )->sum('views');

        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'total_categories' => Category::count(),
                'active_categories' => Category::where('is_active', true)->count(),
                'total_items' => $totalItems,
                'available_items' => $availableItems,
                'unavailable_items' => $totalItems - $availableItems,
                'featured_items' => MenuItem::where('is_featured', true)->count(),
                'new_orders' => Order::where('status', OrderStatus::NEW)->count(),
                // The restaurant's own midnight, not the server's. On a UTC box a
                // Cairo owner (UTC+3) opening the dashboard at 1am still saw
                // yesterday's total sitting there, because the server's day had
                // not turned over yet. MenuViewDaily writes its rows against the
                // same local day, so counter and storage agree.
                'views_today' => $viewsToday,
                'views_yesterday' => $viewsYesterday,

                // Money taken today, against the same local day as the counters
                // above. A cancelled order is not a sale, so it is excluded —
                // which is also why orders_today can be lower than new_orders.
                'sales_today' => $salesToday,
                'orders_today' => $ordersToday,
                'sales_change_pct' => $this->changePct($salesYesterday, $salesToday),

                // Null whenever no till has a shift open — including every tenant
                // that does not run the POS at all, which is the common case.
                'current_shift' => $this->currentShift(),
            ],
        ]);
    }

    /**
     * Sales and order count for one local day, `$daysAgo` back.
     *
     * `created_at` is UTC but the day boundary must be the restaurant's, so the
     * local day is converted to a UTC range and matched on that rather than
     * with a date() on the column — the same reason the view counters above
     * use the tenant's own midnight.
     *
     * @return array{0: float, 1: int}
     */
    private function salesFor(Restaurant $restaurant, int $daysAgo): array
    {
        $tz = $restaurant->localTimezone();
        $day = Carbon::now($tz)->subDays($daysAgo);

        $rows = Order::whereNot('status', OrderStatus::CANCELLED)
            ->whereBetween('created_at', [
                $day->copy()->startOfDay()->utc(),
                $day->copy()->endOfDay()->utc(),
            ])
            ->selectRaw('COUNT(*) as orders, COALESCE(SUM(total), 0) as sales')
            ->first();

        return [round((float) $rows->sales, 2), (int) $rows->orders];
    }

    /**
     * Percentage change from `$from` to `$to`, or null when there is no
     * baseline to compare against — "+100%" off a zero yesterday reads as a
     * real trend when it only means "yesterday was nothing".
     */
    private function changePct(float $from, float $to): ?int
    {
        if ($from <= 0.0) {
            return null;
        }

        return (int) round(($to - $from) / $from * 100);
    }

    /**
     * The one open till shift, summarised for the dashboard.
     *
     * The till reads its own shift through `pos/shifts/*` with a device token;
     * this is the same figures for someone sitting in the back office, who has
     * no device credential. Reusing PosShiftService::expectedCash keeps the
     * drawer number defined in exactly one place — it is the number the close
     * screen will count against, so a second implementation here could only
     * ever disagree with the till.
     *
     * @return array<string, mixed>|null
     */
    private function currentShift(): ?array
    {
        $shift = PosShift::where('status', PosShift::STATUS_OPEN)
            ->latest('opened_at')
            ->first();

        if (! $shift) {
            return null;
        }

        $salesMinor = (int) OrderPayment::where('pos_shift_id', $shift->id)->sum('amount_minor');
        $ordersCount = $shift->orders()->count();

        return [
            'id' => $shift->id,
            'opened_at' => $shift->opened_at?->toIso8601String(),
            'opened_by' => $shift->openedBy?->name,
            'terminal' => $shift->terminal?->name,
            'sales_minor' => $salesMinor,
            'orders_count' => $ordersCount,
            'expected_cash_minor' => $this->shifts->expectedCash($shift),
            // Integer division on purpose: an average is display-only here, and
            // a fractional minor unit is not a thing any currency can show.
            'average_order_minor' => $ordersCount > 0 ? intdiv($salesMinor, $ordersCount) : 0,
        ];
    }
}

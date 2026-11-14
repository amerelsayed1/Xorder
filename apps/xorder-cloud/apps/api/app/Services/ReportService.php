<?php

namespace App\Services;

use App\Enums\OrderStatus;
use App\Models\BillRequest;
use App\Models\Branch;
use App\Models\DiningArea;
use App\Models\InternalReview;
use App\Models\Order;
use App\Models\Restaurant;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Computes the Phase 4 analytics aggregates (products-by-time, dining-area
 * comparison) from the stored order/bill-request/review rows.
 *
 * Everything is aggregated in PHP from the order `items` JSON snapshot: the
 * snapshot only carries a localized product NAME (no product_id/category), so
 * products are keyed by name (BR — order snapshots are immutable). Time-of-day
 * bucketing uses the restaurant's timezone so orders land in the local
 * day-part they actually happened in (BR-010/011).
 */
class ReportService
{
    /** Distinct name used for order lines that carry no usable name. */
    private const UNNAMED = '—';

    /**
     * Products-by-time report.
     *
     * @param  array<string,mixed>  $filters
     * @return array<string,mixed>
     */
    public function productsByTime(Restaurant $restaurant, array $filters): array
    {
        $requested = $filters['group'] ?? 'period';
        $group = in_array($requested, ['hour', 'day'], true) ? $requested : 'period';
        $tz = $this->timezone($restaurant);

        $orders = $this->withinDaysOfWeek(
            $this->withinTimeWindow(
                $this->matchingOrders($restaurant, $filters)->get(['id', 'items', 'created_at']),
                $this->timeWindow($filters),
                $tz,
                'created_at',
            ),
            $this->daysOfWeek($filters),
            $tz,
            'created_at',
        );

        $totalOrders = $orders->count();

        // buckets[bucketKey] = ['orders' => int, 'products' => [name => [...]]]
        $buckets = [];
        // overall[name] = ['quantity','orders_containing','total_sales','per_bucket' => [key=>qty]]
        $overall = [];

        foreach ($orders as $order) {
            $bucketKey = match ($group) {
                'hour' => $this->hourBucket($order->created_at, $tz),
                'day' => $this->dayBucket($order->created_at, $tz),
                default => $this->periodBucket($order->created_at, $tz),
            };

            if (! isset($buckets[$bucketKey])) {
                $buckets[$bucketKey] = ['orders' => 0, 'products' => []];
            }
            $buckets[$bucketKey]['orders']++;

            // Distinct products within this one order (for orders_containing).
            $seenInOrder = [];

            foreach (($order->items ?? []) as $line) {
                $name = $this->lineName($line);
                $qty = max(1, (int) ($line['qty'] ?? 1));
                $sales = (float) ($line['line_total'] ?? 0);

                // Per-bucket product accumulation.
                $bp = $buckets[$bucketKey]['products'][$name]
                    ?? ['quantity' => 0, 'orders_containing' => 0, 'total_sales' => 0.0, '_seen' => []];
                $bp['quantity'] += $qty;
                $bp['total_sales'] += $sales;
                if (! isset($bp['_seen'][$order->id])) {
                    $bp['_seen'][$order->id] = true;
                    $bp['orders_containing']++;
                }
                $buckets[$bucketKey]['products'][$name] = $bp;

                // Overall product accumulation.
                $op = $overall[$name]
                    ?? ['quantity' => 0, 'orders_containing' => 0, 'total_sales' => 0.0, 'per_bucket' => []];
                $op['quantity'] += $qty;
                $op['total_sales'] += $sales;
                $op['per_bucket'][$bucketKey] = ($op['per_bucket'][$bucketKey] ?? 0) + $qty;
                if (! isset($seenInOrder[$name])) {
                    $seenInOrder[$name] = true;
                    $op['orders_containing']++;
                }
                $overall[$name] = $op;
            }
        }

        // Full product table sorted best-first; top/low are disjoint slices of it.
        $allProducts = $this->shapeOverall($overall, $totalOrders);
        $topLimit = 5;

        return [
            'group' => $group,
            'totals' => [
                'orders' => $totalOrders,
                'quantity' => array_sum(array_column($overall, 'quantity')),
                'sales' => round(array_sum(array_column($overall, 'total_sales')), 2),
            ],
            'periods' => $this->shapeBuckets($buckets, $group),
            'products' => $allProducts,
            'top_performers' => array_slice($allProducts, 0, $topLimit),
            // The lowest performers BEYOND the top set — never overlaps top, and
            // empty for a small catalog (so the UI hides the section) rather than
            // repeating the same few items as both "best" and "worst".
            'low_performers' => array_slice(array_reverse(array_slice($allProducts, $topLimit)), 0, $topLimit),
        ];
    }

    /**
     * A flat product table (used by the export), same rows as `products`.
     *
     * @param  array<string,mixed>  $filters
     * @return array<int,array<string,mixed>>
     */
    public function productsTable(Restaurant $restaurant, array $filters): array
    {
        return $this->productsByTime($restaurant, $filters)['products'];
    }

    /**
     * Dining-area comparison report: per-area metrics plus indoor/outdoor and
     * per-branch roll-ups.
     *
     * @param  array<string,mixed>  $filters
     * @return array<string,mixed>
     */
    public function diningAreas(Restaurant $restaurant, array $filters): array
    {
        $areas = DiningArea::query()
            ->when(! empty($filters['branch_id']), fn ($q) => $q->where('branch_id', (int) $filters['branch_id']))
            ->orderBy('display_order')->orderBy('id')
            ->get();

        $branches = Branch::query()->get()->keyBy('id');

        $tz = $this->timezone($restaurant);

        // One pass over the matching orders, grouped by dining area.
        $orders = $this->withinDaysOfWeek(
            $this->withinTimeWindow(
                $this->matchingOrders($restaurant, $filters)
                    ->whereNotNull('dining_area_id')
                    ->get(['id', 'dining_area_id', 'items', 'total', 'created_at']),
                $this->timeWindow($filters),
                $tz,
                'created_at',
            ),
            $this->daysOfWeek($filters),
            $tz,
            'created_at',
        );

        $orderAgg = [];   // area_id => ['orders','sales','products'=>[name=>qty]]
        foreach ($orders as $order) {
            $aid = $order->dining_area_id;
            $agg = $orderAgg[$aid] ?? ['orders' => 0, 'sales' => 0.0, 'products' => []];
            $agg['orders']++;
            $agg['sales'] += (float) $order->total;
            foreach (($order->items ?? []) as $line) {
                $name = $this->lineName($line);
                $agg['products'][$name] = ($agg['products'][$name] ?? 0) + max(1, (int) ($line['qty'] ?? 1));
            }
            $orderAgg[$aid] = $agg;
        }

        // Bill-request timing per area.
        $bills = $this->matchingBillRequests($restaurant, $filters)
            ->get(['dining_area_id', 'requested_at', 'seen_at', 'completed_at']);
        $billAgg = $this->billTimings($bills);

        // Reviews per area.
        $reviews = $this->matchingReviews($restaurant, $filters)
            ->get(['dining_area_id', 'rating']);
        $reviewAgg = $this->reviewStats($reviews);

        $rows = $areas->map(fn (DiningArea $area) => $this->areaRow(
            $area,
            $branches->get($area->branch_id),
            $orderAgg[$area->id] ?? null,
            $billAgg[$area->id] ?? null,
            $reviewAgg[$area->id] ?? null,
        ))->all();

        return [
            'areas' => $rows,
            'by_type' => $this->rollup($rows, 'type'),
            'by_branch' => $this->rollup($rows, 'branch_id', $branches),
            'totals' => $this->rollupTotals($rows),
        ];
    }

    // ---------------------------------------------------------------------
    // Query builders (all tenant-scoped by the global RestaurantScope)
    // ---------------------------------------------------------------------

    /**
     * @param  array<string,mixed>  $filters
     * @return Builder<Order>
     */
    private function matchingOrders(Restaurant $restaurant, array $filters)
    {
        $tz = $this->timezone($restaurant);

        return Order::query()
            // A pending WhatsApp order is not a sale until it is accepted.
            ->where('status', '!=', OrderStatus::PENDING->value)
            ->when(! ($filters['include_cancelled'] ?? false),
                fn ($q) => $q->where('status', '!=', OrderStatus::CANCELLED->value))
            ->when(! empty($filters['branch_id']), fn ($q) => $q->where('branch_id', (int) $filters['branch_id']))
            ->when(! empty($filters['dining_area_id']), fn ($q) => $q->where('dining_area_id', (int) $filters['dining_area_id']))
            ->when(! empty($filters['order_type']), fn ($q) => $q->where('order_type', $filters['order_type']))
            ->when(! empty($filters['area_type']), fn ($q) => $q->whereHas('diningArea',
                fn ($a) => $a->where('type', $filters['area_type'])))
            ->when(! empty($filters['date_from']),
                fn ($q) => $q->where('created_at', '>=', Carbon::parse($filters['date_from'], $tz)->startOfDay()->utc()))
            ->when(! empty($filters['date_to']),
                fn ($q) => $q->where('created_at', '<=', Carbon::parse($filters['date_to'], $tz)->endOfDay()->utc()));
    }

    /**
     * @param  array<string,mixed>  $filters
     * @return Builder<BillRequest>
     */
    private function matchingBillRequests(Restaurant $restaurant, array $filters)
    {
        $tz = $this->timezone($restaurant);

        return BillRequest::query()
            ->when(! empty($filters['branch_id']), fn ($q) => $q->where('branch_id', (int) $filters['branch_id']))
            ->when(! empty($filters['date_from']),
                fn ($q) => $q->where('created_at', '>=', Carbon::parse($filters['date_from'], $tz)->startOfDay()->utc()))
            ->when(! empty($filters['date_to']),
                fn ($q) => $q->where('created_at', '<=', Carbon::parse($filters['date_to'], $tz)->endOfDay()->utc()));
    }

    /**
     * @param  array<string,mixed>  $filters
     * @return Builder<InternalReview>
     */
    private function matchingReviews(Restaurant $restaurant, array $filters)
    {
        $tz = $this->timezone($restaurant);

        return InternalReview::query()
            ->when(! empty($filters['branch_id']), fn ($q) => $q->where('branch_id', (int) $filters['branch_id']))
            ->when(! empty($filters['date_from']),
                fn ($q) => $q->where('created_at', '>=', Carbon::parse($filters['date_from'], $tz)->startOfDay()->utc()))
            ->when(! empty($filters['date_to']),
                fn ($q) => $q->where('created_at', '<=', Carbon::parse($filters['date_to'], $tz)->endOfDay()->utc()));
    }

    // ---------------------------------------------------------------------
    // Bucketing helpers
    // ---------------------------------------------------------------------

    /** Day-part key for an order's local timestamp, or 'other' if unmatched. */
    private function periodBucket(Carbon $createdAt, string $tz): string
    {
        $local = $createdAt->copy()->setTimezone($tz);
        $mins = $local->hour * 60 + $local->minute;

        foreach ((array) config('platform.report_periods', []) as $period) {
            $from = $this->toMinutes($period['from']);
            $to = $this->toMinutes($period['to']);

            $inWindow = $from < $to
                ? ($mins >= $from && $mins < $to)          // same-day window
                : ($mins >= $from || $mins < $to);         // wraps past midnight

            if ($inWindow) {
                return $period['key'];
            }
        }

        return 'other';
    }

    /** Hourly bucket key, e.g. "08:00", for group=hour. */
    private function hourBucket(Carbon $createdAt, string $tz): string
    {
        return str_pad((string) $createdAt->copy()->setTimezone($tz)->hour, 2, '0', STR_PAD_LEFT).':00';
    }

    /** Calendar-day bucket key, e.g. "2026-07-01" (local date), for group=day. */
    private function dayBucket(Carbon $createdAt, string $tz): string
    {
        return $createdAt->copy()->setTimezone($tz)->format('Y-m-d');
    }

    private function toMinutes(string $hhmm): int
    {
        [$h, $m] = array_map('intval', explode(':', $hhmm));

        return $h * 60 + $m;
    }

    /**
     * The optional time-of-day window as [fromMinutes, toMinutes] in the
     * restaurant's local time, or null when neither bound is set. A window whose
     * `from` exceeds `to` wraps past midnight (e.g. 23:00–02:00). Filtering runs
     * in PHP (not SQL) so it honours the restaurant timezone across both the
     * Postgres runtime and the SQLite test DB.
     *
     * @param  array<string,mixed>  $filters
     * @return array{0:int,1:int}|null
     */
    private function timeWindow(array $filters): ?array
    {
        $from = empty($filters['time_from']) ? null : $this->toMinutes($filters['time_from']);
        $to = empty($filters['time_to']) ? null : $this->toMinutes($filters['time_to']);

        if ($from === null && $to === null) {
            return null;
        }

        // An open bound falls back to the full day so a single-sided filter
        // ("from 22:00", "until 06:00") still works.
        return [$from ?? 0, $to ?? 1440];
    }

    /**
     * The optional day-of-week filter as a set of ints (0=Sunday … 6=Saturday,
     * matching Carbon's `dayOfWeek` and JavaScript's `Date.getDay()`), or null
     * when the filter is absent/empty. Out-of-range values are dropped so a
     * stray day never silently excludes every order.
     *
     * @param  array<string,mixed>  $filters
     * @return array<int,int>|null
     */
    private function daysOfWeek(array $filters): ?array
    {
        $raw = $filters['days_of_week'] ?? null;
        if (empty($raw)) {
            return null;
        }

        $days = array_values(array_unique(array_filter(
            array_map('intval', (array) $raw),
            fn ($d) => $d >= 0 && $d <= 6,
        )));

        return $days === [] ? null : $days;
    }

    /**
     * Keep only rows whose local weekday on `$column` is in `$days`. No-op when
     * `$days` is null. Weekday is resolved in the restaurant timezone (in PHP,
     * for the same cross-DB reasons as {@see withinTimeWindow()}).
     *
     * @template TModel of \Illuminate\Database\Eloquent\Model
     *
     * @param  Collection<int,TModel>  $rows
     * @param  array<int,int>|null  $days
     * @return Collection<int,TModel>
     */
    private function withinDaysOfWeek(Collection $rows, ?array $days, string $tz, string $column): Collection
    {
        if ($days === null) {
            return $rows;
        }

        $set = array_flip($days);

        return $rows->filter(function ($row) use ($set, $tz, $column) {
            $ts = $row->{$column};
            if (! $ts instanceof Carbon) {
                return false;
            }

            return isset($set[$ts->copy()->setTimezone($tz)->dayOfWeek]);
        })->values();
    }

    /**
     * Keep only rows whose local time-of-day on `$column` lands in `$window`.
     * No-op when `$window` is null.
     *
     * @template TModel of \Illuminate\Database\Eloquent\Model
     *
     * @param  Collection<int,TModel>  $rows
     * @param  array{0:int,1:int}|null  $window
     * @return Collection<int,TModel>
     */
    private function withinTimeWindow(Collection $rows, ?array $window, string $tz, string $column): Collection
    {
        if ($window === null) {
            return $rows;
        }

        [$from, $to] = $window;

        return $rows->filter(function ($row) use ($from, $to, $tz, $column) {
            $ts = $row->{$column};
            if (! $ts instanceof Carbon) {
                return false;
            }

            $local = $ts->copy()->setTimezone($tz);
            $mins = $local->hour * 60 + $local->minute;

            return $from <= $to
                ? ($mins >= $from && $mins <= $to)   // same-day window (inclusive)
                : ($mins >= $from || $mins <= $to);  // wraps past midnight
        })->values();
    }

    // ---------------------------------------------------------------------
    // Shaping helpers
    // ---------------------------------------------------------------------

    /**
     * @param  array<string,mixed>  $buckets
     * @return array<int,array<string,mixed>>
     */
    private function shapeBuckets(array $buckets, string $group): array
    {
        // Preserve config order for periods; chronological (lexical) for hours
        // ("08:00") and days ("2026-07-01"), both of which sort correctly as text.
        $chronological = in_array($group, ['hour', 'day'], true);
        $order = $chronological
            ? array_keys($buckets)
            : array_merge(array_column((array) config('platform.report_periods', []), 'key'), ['other']);

        if ($chronological) {
            sort($order);
        }

        $out = [];
        foreach ($order as $key) {
            if (! isset($buckets[$key])) {
                continue;
            }
            $bucket = $buckets[$key];
            $products = collect($bucket['products'])
                ->map(fn ($p, $name) => [
                    'name' => $name,
                    'quantity' => $p['quantity'],
                    'orders_containing' => $p['orders_containing'],
                    'total_sales' => round($p['total_sales'], 2),
                ])
                ->sortByDesc('quantity')->values()->all();

            $out[] = [
                'key' => $key,
                'total_orders' => $bucket['orders'],
                'total_quantity' => array_sum(array_column($bucket['products'], 'quantity')),
                'total_sales' => round(array_sum(array_column($bucket['products'], 'total_sales')), 2),
                'products' => $products,
            ];
        }

        return $out;
    }

    /**
     * Turn the overall accumulator into a sorted product table.
     *
     * @param  array<string,mixed>  $overall
     * @return array<int,array<string,mixed>>
     */
    private function shapeOverall(
        array $overall,
        int $totalOrders,
        string $sortBy = 'quantity',
        ?int $limit = null,
        bool $ascending = false,
    ): array {
        $rows = collect($overall)->map(function ($p, $name) use ($totalOrders) {
            $ordersContaining = $p['orders_containing'];
            $mostActive = null;
            if (! empty($p['per_bucket'])) {
                arsort($p['per_bucket']);
                $mostActive = array_key_first($p['per_bucket']);
            }

            return [
                'name' => $name,
                'quantity' => $p['quantity'],
                'orders_containing' => $ordersContaining,
                'total_sales' => round($p['total_sales'], 2),
                'avg_qty_per_order' => $ordersContaining > 0 ? round($p['quantity'] / $ordersContaining, 2) : 0.0,
                'pct_of_orders' => $totalOrders > 0 ? round($ordersContaining / $totalOrders * 100, 1) : 0.0,
                'most_active_period' => $mostActive,
            ];
        });

        $rows = $ascending ? $rows->sortBy($sortBy) : $rows->sortByDesc($sortBy);
        $rows = $rows->values();

        return ($limit !== null ? $rows->take($limit) : $rows)->values()->all();
    }

    // ---------------------------------------------------------------------
    // Dining-area helpers
    // ---------------------------------------------------------------------

    /**
     * @param  Collection<int,BillRequest>  $bills
     * @return array<int,array{count:int,response_sum:float,response_n:int,completion_sum:float,completion_n:int}>
     */
    private function billTimings(Collection $bills): array
    {
        $agg = [];
        foreach ($bills as $bill) {
            $aid = $bill->dining_area_id;
            if ($aid === null) {
                continue;
            }
            $a = $agg[$aid] ?? ['count' => 0, 'response_sum' => 0.0, 'response_n' => 0, 'completion_sum' => 0.0, 'completion_n' => 0];
            $a['count']++;
            if ($bill->requested_at && $bill->seen_at) {
                $a['response_sum'] += $bill->seen_at->getTimestamp() - $bill->requested_at->getTimestamp();
                $a['response_n']++;
            }
            if ($bill->requested_at && $bill->completed_at) {
                $a['completion_sum'] += $bill->completed_at->getTimestamp() - $bill->requested_at->getTimestamp();
                $a['completion_n']++;
            }
            $agg[$aid] = $a;
        }

        return $agg;
    }

    /**
     * @param  Collection<int,InternalReview>  $reviews
     * @return array<int,array{sum:int,n:int,negative:int}>
     */
    private function reviewStats(Collection $reviews): array
    {
        $threshold = (int) config('platform.review_low_rating_threshold', 3);
        $agg = [];
        foreach ($reviews as $review) {
            $aid = $review->dining_area_id;
            if ($aid === null) {
                continue;
            }
            $a = $agg[$aid] ?? ['sum' => 0, 'n' => 0, 'negative' => 0];
            $a['sum'] += (int) $review->rating;
            $a['n']++;
            if ((int) $review->rating <= $threshold) {
                $a['negative']++;
            }
            $agg[$aid] = $a;
        }

        return $agg;
    }

    /**
     * @return array<string,mixed>
     */
    private function areaRow(DiningArea $area, ?Branch $branch, ?array $orders, ?array $bills, ?array $reviews): array
    {
        $totalOrders = $orders['orders'] ?? 0;
        $totalSales = round($orders['sales'] ?? 0.0, 2);

        $mostOrdered = [];
        if (! empty($orders['products'])) {
            $p = $orders['products'];
            arsort($p);
            foreach (array_slice($p, 0, 5, true) as $name => $qty) {
                $mostOrdered[] = ['name' => $name, 'qty' => $qty];
            }
        }

        return [
            'id' => $area->id,
            'branch_id' => $area->branch_id,
            'branch_name_en' => $branch?->name_en,
            'branch_name_ar' => $branch?->name_ar,
            'name_en' => $area->name_en,
            'name_ar' => $area->name_ar,
            'type' => $area->type,
            'total_orders' => $totalOrders,
            'total_sales' => $totalSales,
            'avg_order_value' => $totalOrders > 0 ? round($totalSales / $totalOrders, 2) : 0.0,
            'bill_requests' => $bills['count'] ?? 0,
            'avg_response_seconds' => ($bills['response_n'] ?? 0) > 0 ? (int) round($bills['response_sum'] / $bills['response_n']) : null,
            'avg_completion_seconds' => ($bills['completion_n'] ?? 0) > 0 ? (int) round($bills['completion_sum'] / $bills['completion_n']) : null,
            'avg_review_rating' => ($reviews['n'] ?? 0) > 0 ? round($reviews['sum'] / $reviews['n'], 1) : null,
            'negative_review_count' => $reviews['negative'] ?? 0,
            'most_ordered_products' => $mostOrdered,
        ];
    }

    /**
     * Roll per-area rows up by a dimension (area type or branch).
     *
     * @param  array<int,array<string,mixed>>  $rows
     * @param  Collection<int,Branch>|null  $branches
     * @return array<int,array<string,mixed>>
     */
    private function rollup(array $rows, string $dimension, ?Collection $branches = null): array
    {
        $groups = [];
        foreach ($rows as $row) {
            $key = $row[$dimension];
            $groups[$key][] = $row;
        }

        $out = [];
        foreach ($groups as $key => $group) {
            $agg = $this->rollupTotals($group);
            $agg[$dimension] = $key;
            if ($dimension === 'branch_id' && $branches) {
                $branch = $branches->get($key);
                $agg['branch_name_en'] = $branch?->name_en;
                $agg['branch_name_ar'] = $branch?->name_ar;
            }
            $out[] = $agg;
        }

        return $out;
    }

    /**
     * @param  array<int,array<string,mixed>>  $rows
     * @return array<string,mixed>
     */
    private function rollupTotals(array $rows): array
    {
        $orders = array_sum(array_column($rows, 'total_orders'));
        $sales = round(array_sum(array_column($rows, 'total_sales')), 2);
        $bills = array_sum(array_column($rows, 'bill_requests'));
        $negative = array_sum(array_column($rows, 'negative_review_count'));

        // Weighted average rating across areas that have ratings.
        $ratingSum = 0.0;
        $ratingWeight = 0;
        foreach ($rows as $row) {
            if ($row['avg_review_rating'] !== null) {
                // approximate weight by order count, falling back to 1
                $w = max(1, (int) $row['total_orders']);
                $ratingSum += $row['avg_review_rating'] * $w;
                $ratingWeight += $w;
            }
        }

        return [
            'total_orders' => $orders,
            'total_sales' => $sales,
            'avg_order_value' => $orders > 0 ? round($sales / $orders, 2) : 0.0,
            'bill_requests' => $bills,
            'avg_review_rating' => $ratingWeight > 0 ? round($ratingSum / $ratingWeight, 1) : null,
            'negative_review_count' => $negative,
        ];
    }

    // ---------------------------------------------------------------------
    // Misc
    // ---------------------------------------------------------------------

    private function lineName(mixed $line): string
    {
        $name = trim((string) (is_array($line) ? ($line['name'] ?? '') : ''));

        return $name === '' ? self::UNNAMED : $name;
    }

    private function timezone(Restaurant $restaurant): string
    {
        return $restaurant->localTimezone();
    }
}

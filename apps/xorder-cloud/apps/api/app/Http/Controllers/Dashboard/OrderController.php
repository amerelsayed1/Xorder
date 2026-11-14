<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use App\Services\GuestPagingService;
use App\Support\CsvSafe;
use Closure;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Symfony\Component\HttpFoundation\StreamedResponse;

class OrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $this->validateFilters($request);
        $restaurant = $request->user()->restaurant;

        // Everything the toolbar narrows by EXCEPT the status tabs. The counts
        // are drawn on the tabs themselves, so they have to answer "what would
        // I get if I clicked this?" — which means the search term, the type and
        // the date range apply to them and the selected status does not.
        $scoped = $this->scopedQuery($request, $restaurant);

        $orders = $this->withListRelations($scoped())
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
            ->latest()
            ->paginate(20);

        return OrderResource::collection($orders)
            ->additional(['summary' => $this->summary($restaurant, $scoped)])
            ->response();
    }

    /**
     * The filtered list as CSV — every row the current filters match (status
     * tab included), not just the page on screen. Streamed in chunks so a
     * year of orders never sits in memory at once.
     */
    public function export(Request $request): StreamedResponse
    {
        $this->validateFilters($request);
        $restaurant = $request->user()->restaurant;
        $lang = $restaurant->default_language?->value ?? 'en';
        $tz = $restaurant->localTimezone();

        $query = $this->withListRelations($this->scopedQuery($request, $restaurant)())
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
            ->latest();

        $label = fn (string $key) => __('xorder.orders_export.'.$key, [], $lang);
        $headers = array_map($label, [
            'code', 'placed_at', 'type', 'source', 'branch', 'table', 'customer', 'phone',
            'items', 'total', 'currency', 'status', 'payment', 'handled_by', 'closed_at',
            'minutes_to_complete', 'cancellation_reason', 'note',
        ]);

        $local = fn ($at) => $at?->copy()->setTimezone($tz)->format('Y-m-d H:i');
        $name = fn ($model) => $model ? ($lang === 'ar' ? ($model->name_ar ?: $model->name_en) : ($model->name_en ?: $model->name_ar)) : '';

        $filename = 'orders-'.now($tz)->format('Y-m-d').'.csv';

        return response()->streamDownload(function () use ($query, $headers, $label, $local, $name, $lang) {
            $out = fopen('php://output', 'w');
            fwrite($out, "\xEF\xBB\xBF"); // UTF-8 BOM so Excel reads Arabic correctly
            fputcsv($out, $headers);

            $query->chunk(500, function ($orders) use ($out, $label, $local, $name, $lang) {
                foreach ($orders as $order) {
                    $resource = OrderResource::make($order)->resolve();
                    $items = collect($order->items ?? [])->sum(fn ($i) => (int) ($i['qty'] ?? 1));
                    fputcsv($out, CsvSafe::row([
                        $order->code(),
                        $local($order->created_at),
                        $order->order_type ? __('xorder.orders_export.type_'.$order->order_type, [], $lang) : '',
                        $order->source ? __('xorder.orders_export.source_'.$order->source, [], $lang) : '',
                        $name($order->branch),
                        $order->table?->label ?? '',
                        $order->customer_name ?? '',
                        $order->customer_phone ?? '',
                        $items,
                        $order->total,
                        $order->currency,
                        $label('status_'.$order->status->value),
                        $resource['payment_status'] ?? '',
                        $resource['handled_by_name'] ?? '',
                        $local($order->completed_at ?? $order->cancelled_at),
                        $resource['minutes_to_complete'] ?? '',
                        $order->cancellation_reason ?? '',
                        $order->note ?? '',
                    ]));
                }
            });

            fclose($out);
        }, $filename, ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    private function validateFilters(Request $request): void
    {
        $request->validate([
            'status' => ['sometimes', Rule::in(OrderStatus::values())],
            'order_type' => ['sometimes', Rule::in(['dine_in', 'pickup', 'delivery'])],
            'table_id' => ['sometimes', 'integer'],
            'q' => ['sometimes', 'nullable', 'string', 'max:80'],
            // Restaurant-local calendar days, inclusive at both ends.
            'from' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'nullable', 'date_format:Y-m-d', 'after_or_equal:from'],
        ]);
    }

    /**
     * The list's filters as a reusable query factory (tabs, list and export
     * all start from it).
     *
     * @return Closure(): Builder<Order>
     */
    private function scopedQuery(Request $request, Restaurant $restaurant): Closure
    {
        $term = trim((string) $request->input('q', ''));

        // The toolbar's Pickup tab must also find what the till rang up: the
        // POS sends `takeaway` for the same act (PosOrderService accepts both
        // spellings for the same reason), and those rows are stored as sent.
        // No channel filter anywhere here, on purpose — a till's sale is an
        // order of this restaurant like any other (S2-1, 16 Oct 2026).
        $typeSynonyms = ['pickup' => ['pickup', 'takeaway', 'take_away']];
        $types = $typeSynonyms[$request->input('order_type')] ?? [$request->input('order_type')];

        // A day is the restaurant's day, not the server's: the local midnight
        // boundaries are converted to UTC and matched on the raw column, the
        // same way StatsController counts "today".
        $tz = $restaurant->localTimezone();
        $from = $request->filled('from') ? Carbon::parse($request->input('from'), $tz)->startOfDay()->utc() : null;
        $to = $request->filled('to') ? Carbon::parse($request->input('to'), $tz)->endOfDay()->utc() : null;

        return fn () => Order::query()
            ->when($request->filled('order_type'), fn ($q) => $q->whereIn('order_type', $types))
            ->when($request->filled('table_id'), fn ($q) => $q->where('table_id', $request->integer('table_id')))
            ->when($from, fn ($q) => $q->where('created_at', '>=', $from))
            ->when($to, fn ($q) => $q->where('created_at', '<=', $to))
            ->when($term !== '', fn ($q) => $q->where(function ($w) use ($term) {
                $w->where('customer_name', 'like', '%'.$term.'%')
                    ->orWhere('customer_phone', 'like', '%'.$term.'%');

                // Codes are shown as ORD-<id>, so both halves of what staff read
                // off the screen ("ORD-1024" or just "1024") find the row.
                if (preg_match('/(\\d+)$/', $term, $m)) {
                    $w->orWhere('id', (int) $m[1]);
                }
            }));
    }

    /**
     * What a row needs beyond its own columns: rounds for the item summary,
     * branch for its name, the three people who may have handled it, and the
     * paid sum a till order's payment state is derived from.
     *
     * @param  Builder<Order>  $query
     * @return Builder<Order>
     */
    private function withListRelations(Builder $query): Builder
    {
        return $query
            ->with([
                'rounds.items',
                'branch:id,name_ar,name_en',
                'canceller:id,name',
                'completer:id,name',
                'actingUser:id,name',
                'table:id,label',
            ])
            ->withSum('payments', 'amount_minor');
    }

    /**
     * Tab counts and the day's headline figures, in one trip with the list.
     *
     * Counts come from the same narrowed query the list does, so a tab never
     * promises rows the search would hide. The day figures are deliberately
     * unfiltered — they describe the restaurant's day, not the current view —
     * and turn over at the restaurant's own midnight, the same boundary the
     * views counter and the reports use.
     *
     * @param  Closure(): Builder<Order>  $scoped
     * @return array<string, mixed>
     */
    private function summary(Restaurant $restaurant, Closure $scoped): array
    {
        // toBase() drops the enum cast on `status`, which would otherwise come
        // back as an object and cannot key an array.
        $byStatus = $scoped()->toBase()
            ->selectRaw('status, count(*) as aggregate')
            ->groupBy('status')
            ->pluck('aggregate', 'status');

        $counts = ['all' => (int) $byStatus->sum()];
        foreach (OrderStatus::values() as $status) {
            $counts[$status] = (int) ($byStatus[$status] ?? 0);
        }

        $dayStart = now($restaurant->localTimezone())->startOfDay()->utc();
        $completedToday = Order::where('created_at', '>=', $dayStart)
            ->where('status', OrderStatus::COMPLETED);

        return [
            'counts' => $counts,
            'metrics' => [
                'new_orders' => Order::where('status', OrderStatus::NEW)->count(),
                'pending_orders' => Order::where('status', OrderStatus::PENDING)->count(),
                'orders_today' => Order::where('created_at', '>=', $dayStart)
                    ->where('status', '!=', OrderStatus::PENDING->value)->count(),
                'completed_today' => (clone $completedToday)->count(),
                'sales_today' => number_format((float) $completedToday->sum('total'), 2, '.', ''),
                'currency' => $restaurant->currency?->value,
            ],
        ];
    }

    /** Lightweight badge for the dashboard nav: how many NEW orders wait. */
    public function newCount(): JsonResponse
    {
        return response()->json([
            'data' => [
                'new_orders' => Order::where('status', OrderStatus::NEW)->count(),
                // WhatsApp orders waiting for Accept / Reject.
                'pending_orders' => Order::where('status', OrderStatus::PENDING)->count(),
            ],
        ]);
    }

    /**
     * Accept a pending WhatsApp order: it becomes a normal NEW order. Safe to
     * repeat (a second tap, or two staff at once, finds it already NEW and
     * changes nothing); an order that was rejected or already handled is a 422.
     */
    public function accept(Request $request, Order $order): JsonResponse
    {
        return $this->decide($request, $order, OrderStatus::NEW);
    }

    /** Reject a pending WhatsApp order: it is cancelled, with an optional reason. */
    public function reject(Request $request, Order $order): JsonResponse
    {
        $request->validate(['reason' => ['sometimes', 'nullable', 'string', 'max:255']]);

        return $this->decide($request, $order, OrderStatus::CANCELLED);
    }

    private function decide(Request $request, Order $order, OrderStatus $to): JsonResponse
    {
        $ok = DB::transaction(function () use ($request, $order, $to) {
            // Lock the row so two simultaneous decisions cannot both win; the
            // loser re-reads the new status below. (lockForUpdate is a no-op on
            // SQLite, so the race is only exercised on PostgreSQL.)
            $locked = Order::whereKey($order->id)->lockForUpdate()->firstOrFail();

            if ($locked->status === $to) {
                return true; // already decided the same way: no-op
            }
            if ($locked->status !== OrderStatus::PENDING) {
                return false;
            }

            $locked->status = $to;
            if ($to === OrderStatus::CANCELLED) {
                $reason = trim((string) $request->input('reason', ''));
                $locked->cancelled_at = Carbon::now();
                $locked->cancelled_by = $request->user()->id;
                $locked->cancellation_reason = $reason !== '' ? $reason : null;
            }
            $locked->save();

            AuditLogger::record('order.'.($to === OrderStatus::NEW ? 'accepted' : 'rejected'), [
                'restaurant_id' => $locked->restaurant_id,
                'actor' => $request->user(),
                'auditable' => $locked,
                'description' => sprintf('WhatsApp order %s %s', $locked->code(), $to === OrderStatus::NEW ? 'accepted' : 'rejected'),
            ]);

            // Decided: its "new order" alert is no longer unread.
            Notification::query()
                ->where('type', 'order.created')
                ->where('data->order_id', (string) $locked->id)
                ->whereNull('read_at')
                ->update(['read_at' => Carbon::now()]);

            return true;
        });

        if (! $ok) {
            return response()->json(['message' => __('xorder.messages.order_transition_invalid')], 422);
        }

        return response()->json([
            'data' => OrderResource::make($this->withListRelations(Order::whereKey($order->id))->firstOrFail()),
            'message' => __('xorder.messages.order_updated'),
        ]);
    }

    /**
     * XORD-048: one order as its receipt read — invoice number, till, cashier,
     * table, the money breakdown and each payment. Loaded here and not on the
     * list, so the list never pays for payments it does not show. Another
     * restaurant's order is a 404 through the tenant scope on the binding.
     */
    public function show(Order $order): JsonResponse
    {
        $order = $this->withListRelations(Order::whereKey($order->id))
            ->with([
                'posTerminal:id,name',
                'diningArea:id,name_ar,name_en',
                'payments' => fn ($q) => $q->orderBy('id'),
                'payments.tenderType:id,name,kind',
            ])
            ->firstOrFail();

        return response()->json(['data' => OrderResource::make($order)]);
    }

    public function updateStatus(Request $request, Order $order): JsonResponse
    {
        $request->validate([
            'status' => ['required', Rule::in(OrderStatus::values())],
            // Optional, and only meaningful on a cancellation; ignored otherwise.
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);

        $status = $request->input('status');

        // The visit owns the lifecycle of its single running dine-in bill. If
        // this order were completed independently, the next round would create
        // a second order for the same party. Staff finish the visit instead.
        if ($order->table_visit_id !== null && $order->tableVisit?->status->value === 'OPEN') {
            return response()->json([
                'message' => __('xorder.messages.close_table_visit_instead'),
            ], 422);
        }

        // A pending WhatsApp order is decided with Accept / Reject only, so the
        // alert, the audit entry and the idempotency all go through one path.
        if ($order->status === OrderStatus::PENDING) {
            return response()->json([
                'message' => __('xorder.messages.order_transition_invalid'),
            ], 422);
        }

        // Reject illegal jumps (e.g. reopening a completed/cancelled order back
        // to NEW), which would corrupt the new-orders badge and reporting.
        if (! $order->status->canTransitionTo(OrderStatus::from($status))) {
            return response()->json([
                'message' => __('xorder.messages.order_transition_invalid'),
            ], 422);
        }

        // One commit: the status flip, the pickup stamp and the alert courtesy
        // land together or not at all (a paged order must never read COMPLETED
        // on the queue and PREPARING on the board).
        DB::transaction(function () use ($request, $order, $status) {
            // Who, when and why travel with the CANCELLED state: stamped when an
            // order becomes cancelled, cleared when a cancellation is corrected,
            // so they always describe the order as it stands now. Set outside
            // $fillable on purpose — the server decides them, not the payload.
            $order->status = OrderStatus::from($status);
            if ($status === OrderStatus::CANCELLED->value) {
                $reason = trim((string) $request->input('reason', ''));
                if ($order->isDirty('status')) {
                    $order->cancelled_at = Carbon::now();
                    $order->cancelled_by = $request->user()->id;
                }
                if ($request->has('reason') || $order->isDirty('status')) {
                    $order->cancellation_reason = $reason !== '' ? $reason : null;
                }
            } else {
                $order->cancelled_at = null;
                $order->cancelled_by = null;
                $order->cancellation_reason = null;
            }
            // The completion twin: stamped on becoming COMPLETED, cleared when a
            // completion is corrected away, so "time to complete" never measures
            // a state the order has left.
            if ($status === OrderStatus::COMPLETED->value) {
                if ($order->isDirty('status')) {
                    $order->completed_at = Carbon::now();
                    $order->completed_by = $request->user()->id;
                }
            } else {
                $order->completed_at = null;
                $order->completed_by = null;
            }
            $order->save();

            // Guest paging (BR-8): finishing a paged order from the queue means
            // the diner collected it. Forward-only inside the service (its own
            // transaction becomes a savepoint here); a no-op if the board
            // already said so.
            if ($status === OrderStatus::COMPLETED->value && $order->isPaged()) {
                app(GuestPagingService::class)->transition(
                    $order,
                    PickupStatus::PICKED_UP,
                    GuestPagingService::SOURCE_DASHBOARD,
                    $request->user(),
                );
            }

            // Once an order is acted on (moved out of NEW), its "new order" alert is
            // no longer new — clear the unread dot so the bell stays trustworthy.
            // The order_id linkage is stored (as a string) on the notification's
            // data payload by PublicOrderController when the order is placed.
            if ($status !== OrderStatus::NEW->value) {
                Notification::query()
                    ->where('type', 'order.created')
                    ->where('data->order_id', (string) $order->id)
                    ->whereNull('read_at')
                    ->update(['read_at' => Carbon::now()]);
            }
        });

        return response()->json([
            'data' => OrderResource::make($this->withListRelations(Order::whereKey($order->id))->firstOrFail()),
            'message' => __('xorder.messages.order_updated'),
        ]);
    }
}

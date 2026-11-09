<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Services\GuestPagingService;
use Closure;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class OrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'status' => ['sometimes', Rule::in(OrderStatus::values())],
            'order_type' => ['sometimes', Rule::in(['dine_in', 'pickup', 'delivery'])],
            'table_id' => ['sometimes', 'integer'],
            'q' => ['sometimes', 'nullable', 'string', 'max:80'],
        ]);

        $term = trim((string) $request->input('q', ''));

        // The toolbar's Pickup tab must also find what the till rang up: the
        // POS sends `takeaway` for the same act (PosOrderService accepts both
        // spellings for the same reason), and those rows are stored as sent.
        // No channel filter anywhere here, on purpose — a till's sale is an
        // order of this restaurant like any other (S2-1, 16 Oct 2026).
        $typeSynonyms = ['pickup' => ['pickup', 'takeaway', 'take_away']];
        $types = $typeSynonyms[$request->input('order_type')] ?? [$request->input('order_type')];

        // Everything the toolbar narrows by EXCEPT the status tabs. The counts
        // are drawn on the tabs themselves, so they have to answer "what would
        // I get if I clicked this?" — which means the search term and the type
        // filter apply to them and the selected status does not.
        $scoped = fn () => Order::query()
            ->when($request->filled('order_type'), fn ($q) => $q->whereIn('order_type', $types))
            ->when($request->filled('table_id'), fn ($q) => $q->where('table_id', $request->integer('table_id')))
            ->when($term !== '', fn ($q) => $q->where(function ($w) use ($term) {
                $w->where('customer_name', 'like', '%'.$term.'%')
                    ->orWhere('customer_phone', 'like', '%'.$term.'%');

                // Codes are shown as ORD-<id>, so both halves of what staff read
                // off the screen ("ORD-1024" or just "1024") find the row.
                if (preg_match('/(\\d+)$/', $term, $m)) {
                    $w->orWhere('id', (int) $m[1]);
                }
            }));

        $orders = $scoped()
            ->with('rounds.items')
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
            ->latest()
            ->paginate(20);

        return OrderResource::collection($orders)
            ->additional(['summary' => $this->summary($request->user()->restaurant, $scoped)])
            ->response();
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
                'orders_today' => Order::where('created_at', '>=', $dayStart)->count(),
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
            'data' => ['new_orders' => Order::where('status', OrderStatus::NEW)->count()],
        ]);
    }

    public function updateStatus(Request $request, Order $order): JsonResponse
    {
        $request->validate([
            'status' => ['required', Rule::in(OrderStatus::values())],
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
            $order->update(['status' => $status]);

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
            'data' => OrderResource::make($order->fresh()->load('rounds.items')),
            'message' => __('xorder.messages.order_updated'),
        ]);
    }
}

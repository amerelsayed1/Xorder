<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use App\Services\GuestPagingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

/**
 * Guest paging — the counter's board (Preparing / Following on phone / Ready /
 * Picked up) and its two buttons. Reads carry orders.read, writes orders.update,
 * exactly like the order queue; the token itself is never in this output.
 */
class PickupBoardController extends Controller
{
    public function __construct(private readonly GuestPagingService $paging) {}

    /** Today's paged orders for one tablet, oldest first, polled every few seconds. */
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'branch_id' => ['sometimes', 'integer'],
        ]);

        $restaurant = $request->user()->restaurant;
        $now = Carbon::now();
        $dayStart = $now->copy()->setTimezone($restaurant->localTimezone())->startOfDay()->utc();
        $linger = $now->copy()->subMinutes(GuestPagingService::BOARD_LINGER_MINUTES);

        $orders = Order::query()
            ->whereNotNull('pickup_token')
            ->where('created_at', '>=', $dayStart)
            ->where('status', '!=', OrderStatus::CANCELLED->value)
            ->where(fn ($q) => $q
                ->where('pickup_status', '!=', PickupStatus::PICKED_UP->value)
                ->orWhere('picked_up_at', '>=', $linger))
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            // `id` breaks same-second ties, so a rush keeps one order between
            // polls on PostgreSQL too (and the ETag stays stable).
            ->orderBy('created_at')
            ->orderBy('id')
            ->get();

        $rows = $orders->map(fn (Order $o) => [
            'id' => $o->id,
            'ref' => $o->pickup_display_ref ?? $o->code(),
            'pickup_status' => $o->pickup_status?->value,
            'followed_at' => $o->pickup_followed_at?->toIso8601String(),
            'ready_at' => $o->ready_at?->toIso8601String(),
            'acknowledged_at' => $o->acknowledged_at?->toIso8601String(),
            'picked_up_at' => $o->picked_up_at?->toIso8601String(),
            'call_out' => $this->paging->isCallOut($o, $now),
            'order_type' => $o->order_type,
            'channel' => $o->channel,
            'customer_name' => $o->customer_name,
            'created_at' => $o->created_at?->toIso8601String(),
            'branch_id' => $o->branch_id,
        ])->values()->all();

        $response = response()->json([
            'data' => $rows,
            'meta' => [
                'call_out_minutes' => (int) config('platform.guest_paging.call_out_minutes', 3),
                'linger_minutes' => GuestPagingService::BOARD_LINGER_MINUTES,
            ],
        ]);

        // Same idle-poll economy as PulseController: an unchanged board is a
        // 304 with no body.
        $response->setEtag(md5(json_encode($rows)));
        $response->isNotModified($request);

        return $response;
    }

    /** Ready / Picked up from the tablet. Forward only (BR-1); 422 otherwise. */
    public function update(Request $request, Order $order): JsonResponse
    {
        $request->validate([
            'status' => ['required', Rule::in([PickupStatus::READY->value, PickupStatus::PICKED_UP->value])],
        ]);

        $result = $this->paging->transition(
            $order,
            PickupStatus::from($request->input('status')),
            GuestPagingService::SOURCE_DASHBOARD,
            $request->user(),
        );

        if ($result['reason'] === 'not_paged') {
            return response()->json(['message' => __('xorder.messages.order_not_paged')], 422);
        }
        if ($result['reason'] === 'cancelled') {
            return response()->json(['message' => __('xorder.messages.order_transition_invalid')], 422);
        }
        if ($result['reason'] === 'backwards') {
            return response()->json(['message' => __('xorder.messages.pickup_transition_invalid')], 422);
        }

        return response()->json([
            'data' => OrderResource::make($order->fresh()->load('rounds.items')),
            'message' => __('xorder.messages.pickup_updated'),
        ]);
    }
}

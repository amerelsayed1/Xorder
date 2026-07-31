<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Notification;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Validation\Rule;

class OrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'status' => ['sometimes', Rule::in(OrderStatus::values())],
            'table_id' => ['sometimes', 'integer'],
        ]);

        $orders = Order::query()
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
            ->when($request->filled('table_id'), fn ($q) => $q->where('table_id', $request->integer('table_id')))
            ->latest()
            ->paginate(20);

        return OrderResource::collection($orders)->response();
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

        // Reject illegal jumps (e.g. reopening a completed/cancelled order back
        // to NEW), which would corrupt the new-orders badge and reporting.
        if (! $order->status->canTransitionTo(OrderStatus::from($status))) {
            return response()->json([
                'message' => __('xorder.messages.order_transition_invalid'),
            ], 422);
        }

        $order->update(['status' => $status]);

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

        return response()->json([
            'data' => OrderResource::make($order->fresh()),
            'message' => __('xorder.messages.order_updated'),
        ]);
    }
}

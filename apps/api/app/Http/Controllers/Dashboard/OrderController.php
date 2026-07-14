<?php

namespace App\Http\Controllers\Dashboard;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\OrderResource;
use App\Models\Order;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class OrderController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $request->validate([
            'status' => ['sometimes', Rule::in(OrderStatus::values())],
        ]);

        $orders = Order::query()
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->input('status')))
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

        $order->update(['status' => $request->input('status')]);

        return response()->json([
            'data' => OrderResource::make($order->fresh()),
            'message' => __('xorder.messages.order_updated'),
        ]);
    }
}

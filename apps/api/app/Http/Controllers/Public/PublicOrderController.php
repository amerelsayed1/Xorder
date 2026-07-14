<?php

namespace App\Http\Controllers\Public;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreOrderRequest;
use App\Models\Order;
use App\Services\PublicMenuService;
use Illuminate\Http\JsonResponse;

class PublicOrderController extends Controller
{
    public function __construct(private readonly PublicMenuService $menu) {}

    /**
     * Record a guest order before the WhatsApp handoff so the restaurant has
     * durable order history — the wa.me link alone leaves no trace if the
     * customer never sends the message.
     */
    public function store(StoreOrderRequest $request, string $slug): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null || ! $this->menu->isVisible($restaurant)) {
            return response()->json(['message' => __('xorder.messages.restaurant_not_found')], 404);
        }

        if (! $restaurant->ordering_enabled) {
            return response()->json(['message' => __('xorder.messages.ordering_disabled')], 422);
        }

        $order = new Order($request->validated() + [
            'status' => OrderStatus::NEW->value,
            'currency' => $restaurant->currency->value,
            'source' => 'whatsapp',
        ]);
        $order->restaurant_id = $restaurant->id;
        $order->save();

        return response()->json([
            'data' => ['id' => $order->id, 'code' => $order->code()],
            'message' => __('xorder.messages.order_received'),
        ], 201);
    }
}

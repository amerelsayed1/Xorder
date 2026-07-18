<?php

namespace App\Http\Controllers\Public;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreOrderRequest;
use App\Models\Customer;
use App\Models\Order;
use App\Services\PublicMenuService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

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

        // Pin the tenant so the customer directory upsert below is scoped and
        // stamped to this restaurant (public request has no auth context).
        TenantContext::overrideId($restaurant->id);

        [$customer, $address] = $this->resolveCustomer($request->validated());

        $order = new Order($request->validated() + [
            'status' => OrderStatus::NEW->value,
            'currency' => $restaurant->currency->value,
            'source' => 'whatsapp',
        ]);
        $order->restaurant_id = $restaurant->id;
        $order->customer_id = $customer?->id;
        $order->customer_address_id = $address?->id;
        $order->save();

        return response()->json([
            'data' => ['id' => $order->id, 'code' => $order->code()],
            'message' => __('xorder.messages.order_received'),
        ], 201);
    }

    /**
     * Upsert the directory customer (by phone) and, for deliveries, remember
     * the address. Best-effort: a hiccup here must never block the order.
     *
     * @return array{0: ?Customer, 1: ?\App\Models\CustomerAddress}
     */
    private function resolveCustomer(array $data): array
    {
        $phone = trim((string) ($data['customer_phone'] ?? ''));
        if ($phone === '') {
            return [null, null];
        }

        try {
            $customer = Customer::firstOrNew(['phone' => $phone]);
            if (! empty($data['customer_name'])) {
                $customer->name = $data['customer_name'];
            }
            if (! empty($data['customer_email'])) {
                $customer->email = $data['customer_email'];
            }
            $customer->save();

            $address = null;
            $text = trim((string) ($data['customer_address'] ?? ''));
            if ($text !== '') {
                $address = $customer->addresses()->where('address', $text)->first();
                if ($address === null) {
                    $address = $customer->addresses()->create([
                        'label' => $data['address_label'] ?? null,
                        'address' => $text,
                        'is_default' => $customer->addresses()->count() === 0,
                    ]);
                }
            }

            return [$customer, $address];
        } catch (\Throwable $e) {
            Log::warning('Customer upsert failed on order', ['error' => $e->getMessage()]);

            return [null, null];
        }
    }
}

<?php

namespace App\Http\Controllers\Public;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Http\Controllers\Controller;
use App\Models\Order;
use App\Services\GuestPagingService;
use App\Support\PublicImageUrl;
use App\Support\SafeUrl;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Carbon;

/**
 * Guest paging — the diner's side (docs/features/guest-paging, BR-3..BR-7).
 *
 * The 40-character token on the receipt or in the success screen is the only
 * credential: no slug, no account, no phone. The page polls `show`, says
 * "following" once, acknowledges "On my way" when READY, and may leave a web
 * push token. The payload is the order reference and its state — never line
 * items, prices, the customer's name or phone (BR-4).
 */
class PublicOrderTrackingController extends Controller
{
    public function __construct(private readonly GuestPagingService $paging) {}

    /** GET /public/orders/track/{token} */
    public function show(Request $request, string $token): JsonResponse
    {
        $order = $this->resolve($token);

        return $this->respond($request, $order);
    }

    /** POST /public/orders/track/{token}/follow — the page opened ("Following on phone"). */
    public function follow(Request $request, string $token): JsonResponse
    {
        $order = $this->resolve($token);

        if ($order->pickup_followed_at === null) {
            $order->forceFill(['pickup_followed_at' => Carbon::now()])->save();
        }

        return $this->respond($request, $order);
    }

    /** POST /public/orders/track/{token}/ack — "On my way", only while READY. */
    public function acknowledge(Request $request, string $token): JsonResponse
    {
        $order = $this->resolve($token);

        // D-6: nothing to come for on a cancelled order, even one that was
        // READY when it was cancelled.
        if ($order->status === OrderStatus::CANCELLED) {
            return response()->json(['message' => __('xorder.messages.order_transition_invalid')], 422);
        }
        if ($order->pickup_status !== PickupStatus::READY) {
            return response()->json(['message' => __('xorder.messages.pickup_not_ready')], 422);
        }
        if ($order->acknowledged_at === null) {
            $order->forceFill(['acknowledged_at' => Carbon::now()])->save();
        }

        return $this->respond($request, $order);
    }

    /** POST /public/orders/track/{token}/push-token — the diner allowed notifications. */
    public function storePushToken(Request $request, string $token): Response
    {
        $request->validate([
            'token' => ['required', 'string', 'max:512'],
        ]);

        $this->resolve($token)->forceFill(['pickup_push_token' => $request->input('token')])->save();

        return response()->noContent();
    }

    /** DELETE /public/orders/track/{token}/push-token */
    public function destroyPushToken(string $token): Response
    {
        $this->resolve($token)->forceFill(['pickup_push_token' => null])->save();

        return response()->noContent();
    }

    /**
     * Token → order, across tenants (the URL carries no slug; the token is
     * unique platform-wide, BR-3). Unknown, expired and feature-off all end
     * here; nothing about a foreign tenant is revealed either way.
     */
    private function resolve(string $token): Order
    {
        $order = Order::withoutGlobalScopes()
            ->with(['restaurant.features', 'branch'])
            ->where('pickup_token', $token)
            ->first();

        if ($order === null) {
            abort(404, __('xorder.messages.order_not_found'));
        }

        $ttl = (int) config('platform.guest_paging.tracking_ttl_hours', 48);
        if ($order->created_at !== null && $order->created_at->lt(Carbon::now()->subHours($ttl))) {
            abort(404, __('xorder.messages.order_not_found'));
        }

        $restaurant = $order->restaurant;
        if ($restaurant === null || ! $restaurant->isPubliclyVisible() || ! $restaurant->hasFeature('guest_paging')) {
            abort(403, __('xorder.errors.feature_disabled'));
        }

        return $order;
    }

    /** Same idle-poll economy as the pulse: an unchanged page is a 304 with no body. */
    private function respond(Request $request, Order $order): JsonResponse
    {
        $payload = $this->present($order);

        $response = response()->json(['data' => $payload]);
        $response->setEtag(md5(json_encode($payload)));
        $response->isNotModified($request);

        return $response;
    }

    /** @return array<string,mixed> */
    private function present(Order $order): array
    {
        $restaurant = $order->restaurant;
        $ar = app()->getLocale() === 'ar';
        $pickedUp = $order->pickup_status === PickupStatus::PICKED_UP;

        return [
            'ref' => $order->pickup_display_ref ?? $order->code(),
            'status' => $order->pickup_status?->value,
            'order_status' => $order->status->value,
            'placed_at' => $order->created_at?->toIso8601String(),
            'ready_at' => $order->ready_at?->toIso8601String(),
            'acknowledged_at' => $order->acknowledged_at?->toIso8601String(),
            'picked_up_at' => $order->picked_up_at?->toIso8601String(),
            'order_type' => $order->order_type,
            'call_out' => $this->paging->isCallOut($order),
            'restaurant' => [
                'name' => $ar
                    ? ($restaurant->name_ar ?: $restaurant->name_en)
                    : ($restaurant->name_en ?: $restaurant->name_ar),
                // Both names and the restaurant's language settings, so the page
                // opens in the language the restaurant chose (as the menu does)
                // and can switch without another request.
                'name_ar' => $restaurant->name_ar ?: $restaurant->name_en,
                'name_en' => $restaurant->name_en ?: $restaurant->name_ar,
                'default_language' => $restaurant->default_language?->value ?? 'ar',
                'bilingual' => (bool) $restaurant->bilingual,
                // Same rewrite as RestaurantPublicResource, so the page treats
                // both the same way.
                'logo_url' => PublicImageUrl::relative($restaurant->logo_url),
                'brand_color' => $restaurant->brand_color,
            ],
            'branch' => $order->branch
                ? ['name' => $ar
                    ? ($order->branch->name_ar ?: $order->branch->name_en)
                    : ($order->branch->name_en ?: $order->branch->name_ar)]
                : null,
            // The review invitation only once the food is in the diner's hands.
            'review_public_url' => $pickedUp ? SafeUrl::forLink($restaurant->review_public_url) : null,
            'review_thank_you' => $pickedUp
                ? ($ar
                    ? ($restaurant->review_thank_you_ar ?: $restaurant->review_thank_you_en)
                    : ($restaurant->review_thank_you_en ?: $restaurant->review_thank_you_ar))
                : null,
        ];
    }
}

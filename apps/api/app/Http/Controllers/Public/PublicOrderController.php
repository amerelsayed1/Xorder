<?php

namespace App\Http\Controllers\Public;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreOrderRequest;
use App\Models\MenuSession;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderRound;
use App\Services\BranchEgressIpService;
use App\Services\CustomerDirectory;
use App\Services\DinerOrderPricing;
use App\Services\GuestPagingService;
use App\Services\NotificationService;
use App\Services\PublicMenuService;
use App\Services\TableVisitService;
use App\Support\TenantContext;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class PublicOrderController extends Controller
{
    public function __construct(
        private readonly PublicMenuService $menu,
        private readonly CustomerDirectory $directory,
    ) {}

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

        // The plan decides whether this menu takes orders at all: with no
        // entitled ordering channel the public menu is display-only. Read the
        // plan-capped mode, never the raw column, so a plan change is honoured
        // immediately without waiting for a reconciliation.
        $mode = $restaurant->effectiveOrderingMode();

        if ($mode === null) {
            return response()->json(['message' => __('xorder.messages.ordering_disabled')], 422);
        }

        // The owner's own switch, independent of the plan: they are entitled to
        // take orders but have paused them (kitchen swamped, closing early).
        // Enforced here and not only in the UI — the menu is a SPA and a stale
        // tab would otherwise keep posting into a closed kitchen.
        //
        // Deliberately the same reply as an unentitled menu: a diner does not
        // need to be told which of the two reasons applies, only that ordering
        // is not available. The distinction stays internal.
        if (! $restaurant->accepts_orders) {
            return response()->json(['message' => __('xorder.messages.ordering_disabled')], 422);
        }

        // A WhatsApp restaurant's order is recorded too (live-board-to-pos D6),
        // but as PENDING: it is not a real order until an employee accepts it,
        // so it stays out of the kitchen, the badge, sales and reports.
        $pending = $mode->usesWhatsapp();

        $data = $request->validated();

        // The restaurant answers a WhatsApp order by messaging the diner
        // (live-board-to-pos D15), so it cannot be taken without a number.
        if ($pending && blank($data['customer_phone'] ?? null)) {
            return response()->json(['message' => __('xorder.messages.whatsapp_order_needs_phone')], 422);
        }

        // Priced here, from the menu, before anything is written (XORD-047).
        // The phone's line_total and total are discarded: they were how a
        // modified request set its own price. An item that cannot be sold
        // throws a 422 now, while there is still nothing to roll back.
        //
        // Before the tenant is pinned below, not inside it: the menu loader
        // pins and then CLEARS the tenant itself, which would leave the
        // directory upsert and the order write unscoped.
        $priced = app(DinerOrderPricing::class)->price(
            $restaurant,
            $data['items'],
            $data['lang'] ?? $restaurant->default_language->value,
        );
        $data['items'] = $priced['items'];
        // Clamped to the total column's capacity (decimal(10,2)) exactly as
        // before: 100 lines of a very expensive item must not be a 500.
        $data['total'] = min((float) $priced['total'], 99999999.99);
        unset($data['lang']);

        // Pin the tenant so the customer directory upsert below is scoped and
        // stamped to this restaurant (public request has no auth context). The
        // override is released in a finally so a thrown exception can never leak
        // the pin into a later request on a reused worker (Octane/queue).
        TenantContext::overrideId($restaurant->id);

        try {

            [$customer, $address] = $this->directory->upsert($data);

            // session_token is a lookup key, not a column on the order — it is
            // consumed by bindTableSession below. The email, address and its
            // label belong to the customer directory (upserted just above), not
            // to the order row. Dropping them explicitly rather than leaving mass
            // assignment to discard them: outside production the model is strict
            // and an unknown key is a 500, which turned every menu order that
            // carried the (always present, often null) email field into a
            // silent failure behind the diner's success dialog.
            unset($data['session_token'], $data['customer_email'], $data['customer_address'], $data['address_label']);

            $order = DB::transaction(function () use ($data, $restaurant, $mode, $pending, $customer, $address, $request) {
                // A pending WhatsApp order never joins a table visit: there is
                // no seated bill for it to be merged into.
                $session = $pending ? null : $this->resolveTableSession(
                    $restaurant->id,
                    $request->input('session_token'),
                    $request->ip(),
                );

                $order = null;
                if ($session?->table_visit_id) {
                    // Lock the visit so simultaneous devices at the same table
                    // cannot both create an OPEN order or choose the same round.
                    $session->tableVisit()->lockForUpdate()->firstOrFail();
                    $order = Order::withoutGlobalScopes()
                        ->where('table_visit_id', $session->table_visit_id)
                        ->where('status', OrderStatus::NEW->value)
                        ->lockForUpdate()
                        ->first();
                }

                if ($order === null) {
                    $order = new Order($data + [
                        'status' => ($pending ? OrderStatus::PENDING : OrderStatus::NEW)->value,
                        'currency' => $restaurant->currency->value,
                        'source' => $mode->usesWhatsapp() ? 'whatsapp' : 'system',
                    ]);
                    $order->restaurant_id = $restaurant->id;
                    $order->customer_id = $customer?->id;
                    $order->customer_address_id = $address?->id;

                    if ($session !== null) {
                        $order->menu_session_id = $session->id;
                        $order->table_visit_id = $session->table_visit_id;
                        $order->table_id = $session->table_id;
                        $order->dining_area_id = $session->dining_area_id;
                        $order->branch_id = $session->branch_id;
                        $order->order_type = 'dine_in';
                    }

                    // Guest paging (BR-2/BR-3): a counter order the diner will
                    // collect gets its tracking token here, at creation, so the
                    // success screen can open the page at once. Never a round
                    // of a seated table — that is served, not collected.
                    $paging = app(GuestPagingService::class);
                    if (! $pending && $paging->isEligible($restaurant, $order->order_type, $session?->table_visit_id !== null)) {
                        $order->pickup_token = GuestPagingService::generateToken();
                        $order->pickup_status = PickupStatus::PREPARING->value;
                    }
                    $order->save();
                } else {
                    $existingItems = $order->items ?? [];
                    $order->forceFill([
                        'items' => array_merge($existingItems, $data['items']),
                        'total' => min((float) $order->total + (float) $data['total'], 99999999.99),
                        'customer_id' => $order->customer_id ?? $customer?->id,
                        'customer_address_id' => $order->customer_address_id ?? $address?->id,
                        'customer_name' => $order->customer_name ?: ($data['customer_name'] ?? null),
                        'customer_phone' => $order->customer_phone ?: ($data['customer_phone'] ?? null),
                    ])->save();
                }

                $this->recordRound($order, $session, $data);
                if ($session !== null) {
                    $session->forceFill(['last_activity_at' => now()])->save();
                }

                return $order;
            });
        } finally {
            TenantContext::clearOverride();
        }

        // Notify the restaurant's admin devices — after the response is flushed
        // so the FCM round-trip never delays order recording. Best-effort.
        $lang = $restaurant->default_language->value;
        $title = __('xorder.messages.push_new_order_title', [], $lang);
        $body = __('xorder.messages.push_new_order_body', [
            'code' => $order->code(),
            'total' => $order->total,
            'currency' => $order->currency,
        ], $lang);
        app()->terminating(function () use ($restaurant, $order, $title, $body) {
            app(NotificationService::class)->toRestaurant(
                $restaurant->id,
                'order.created',
                $title,
                $body,
                ['order_id' => (string) $order->id],
                '/admin/orders',
            );
        });

        $payload = ['id' => $order->id, 'code' => $order->code()];
        if ($order->isPaged()) {
            $payload['pickup_token'] = $order->pickup_token;
            $payload['tracking_url'] = $restaurant->trackingUrl($order->pickup_token);
        }

        return response()->json([
            'data' => $payload,
            'message' => __('xorder.messages.order_received'),
        ], 201);
    }

    /**
     * Expose only a guest order's lifecycle status so the menu SPA can decide,
     * on the diner's return, whether the order is closed (COMPLETED) and it's
     * time to invite private feedback. Deliberately minimal: no customer or
     * order detail is returned — status alone is not sensitive, and the lookup
     * is scoped to this restaurant so a foreign id resolves to 404, not a leak.
     */
    public function status(string $slug, int $id): JsonResponse
    {
        $restaurant = $this->menu->findBySlug($slug);

        if ($restaurant === null || ! $this->menu->isVisible($restaurant)) {
            return response()->json(['message' => __('xorder.messages.restaurant_not_found')], 404);
        }

        // Public request carries no auth context, so the tenant global scope
        // can't apply — scope the lookup to this restaurant by hand.
        $order = Order::withoutGlobalScopes()
            ->where('restaurant_id', $restaurant->id)
            ->find($id);

        if ($order === null) {
            return response()->json(['message' => __('xorder.messages.order_not_found')], 404);
        }

        return response()->json(['data' => ['status' => $order->status->value]]);
    }

    /**
     * Stamp the order with its table context from a menu session, if the token
     * resolves to one belonging to this restaurant.
     */
    private function resolveTableSession(int $restaurantId, ?string $token, ?string $clientIp = null): ?MenuSession
    {
        if (empty($token)) {
            return null;
        }

        $session = MenuSession::withoutGlobalScopes()
            ->with(['branch', 'table', 'tableVisit'])
            ->where('restaurant_id', $restaurantId)
            ->where('session_token', $token)
            ->first();

        if ($session === null) {
            return null;
        }

        if ($session->tableVisit === null) {
            app(TableVisitService::class)->attachSession($session);
        }

        if (! $session->isUsable() || $session->tableVisit === null
            || $session->tableVisit->status->value !== 'OPEN') {
            abort(422, __('xorder.messages.session_expired'));
        }

        // Re-check the Wi-Fi requirement at order time for a branch that
        // enforces it. The scan-time check alone would be trivially sidestepped
        // by joining the Wi-Fi to open the session and then switching back to
        // mobile data to order, which is the same order the requirement means
        // to refuse. Unlike a stale token this is not silently downgraded to an
        // untagged order — the whole point is that it must not go through.
        if ($session->branch?->require_branch_wifi
            && app(BranchEgressIpService::class)->matches($session->branch, $clientIp) !== true) {
            abort(422, __('xorder.messages.table_requires_branch_wifi'));
        }

        return $session;
    }

    /** Persist a kitchen-visible submission round while retaining orders.items for compatibility. */
    private function recordRound(Order $order, ?MenuSession $session, array $data): void
    {
        $sequence = OrderRound::withoutGlobalScopes()->where('order_id', $order->id)->max('sequence') + 1;
        $round = new OrderRound([
            'order_id' => $order->id,
            'menu_session_id' => $session?->id,
            'sequence' => $sequence,
            'total' => $data['total'],
            'note' => $data['note'] ?? null,
            'submitted_at' => now(),
        ]);
        $round->restaurant_id = $order->restaurant_id;
        $round->save();

        foreach ($data['items'] as $line) {
            $quantity = (int) $line['qty'];
            $item = new OrderItem([
                'order_id' => $order->id,
                'order_round_id' => $round->id,
                'name' => $line['name'],
                'quantity' => $quantity,
                'variant' => $line['variant'] ?? null,
                'options' => $line['options'] ?? [],
                'note' => $line['note'] ?? null,
                'unit_price' => $line['unit_price'],
                'line_total' => $line['line_total'],
            ]);
            $item->restaurant_id = $order->restaurant_id;
            // Server-priced (XORD-047): the menu item it was priced from, and
            // the figures in minor units, written beside the decimals the
            // dashboard reads — the columns POS orders already fill.
            $item->forceFill([
                'menu_item_id' => $line['menu_item_id'] ?? null,
                'unit_price_minor' => (int) round((float) $line['unit_price'] * 100),
                'line_total_minor' => (int) round((float) $line['line_total'] * 100),
                'price_source' => $line['price_source'] ?? 'server',
            ]);
            $item->save();
        }
    }
}

<?php

namespace App\Http\Controllers\Public;

use App\Enums\OrderStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Public\StoreOrderRequest;
use App\Models\MenuSession;
use App\Models\Order;
use App\Models\OrderItem;
use App\Models\OrderRound;
use App\Services\BranchEgressIpService;
use App\Services\CustomerDirectory;
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

        // WhatsApp-only restaurants take orders through WhatsApp, not the system,
        // so there is no order record to create here.
        if (! $mode->usesSystem()) {
            return response()->json(['message' => __('xorder.messages.ordering_disabled')], 422);
        }

        // Pin the tenant so the customer directory upsert below is scoped and
        // stamped to this restaurant (public request has no auth context). The
        // override is released in a finally so a thrown exception can never leak
        // the pin into a later request on a reused worker (Octane/queue).
        TenantContext::overrideId($restaurant->id);

        try {
            $data = $request->validated();

            // Recompute the order total from the submitted line totals rather than
            // trusting the client's `total`. Line prices are still a customer
            // snapshot (the menu is fulfilled over WhatsApp, no payment taken and
            // the payload carries no item ids to re-price against), but the stored
            // total can no longer contradict its own line items — a forged
            // `total` of 0 or 999999 is normalized before it reaches history,
            // stats and reports.
            //
            // Clamp to the total column's capacity (decimal(10,2)): each of up to
            // 100 line_totals is capped at 1,000,000, so the raw sum can reach
            // 100,000,000 and overflow the column (a 500 on this public endpoint).
            $sum = collect($data['items'] ?? [])
                ->sum(fn ($item) => (float) ($item['line_total'] ?? 0));
            $data['total'] = min($sum, 99999999.99);

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

            $order = DB::transaction(function () use ($data, $restaurant, $mode, $customer, $address, $request) {
                $session = $this->resolveTableSession(
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
                        'status' => OrderStatus::NEW->value,
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

        return response()->json([
            'data' => ['id' => $order->id, 'code' => $order->code()],
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
                'unit_price' => round((float) $line['line_total'] / $quantity, 2),
                'line_total' => $line['line_total'],
            ]);
            $item->restaurant_id = $order->restaurant_id;
            $item->save();
        }
    }
}

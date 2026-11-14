<?php

namespace App\Services;

use App\Enums\OrderStatus;
use App\Enums\PickupStatus;
use App\Models\Notification;
use App\Models\Order;
use App\Models\Restaurant;
use App\Models\User;
use Carbon\CarbonInterface;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/**
 * Guest paging (docs/features/guest-paging): the single owner of the pickup
 * lifecycle. The dashboard board, the existing order-status endpoint and the
 * POS pickup event (POS-BE-033) all come through transition(), so the rule
 * "forward only, each stamp set once" has exactly one implementation.
 */
class GuestPagingService
{
    /** Paged unless the owner says otherwise (BR-2). */
    public const DEFAULT_ORDER_TYPES = ['takeaway', 'pickup', 'drive_thru'];

    public const SOURCE_POS = 'pos';

    public const SOURCE_DASHBOARD = 'dashboard';

    /** A picked-up order stays on the board this long, then drops off. */
    public const BOARD_LINGER_MINUTES = 30;

    /** @return list<string> */
    public function pagedOrderTypes(Restaurant $restaurant): array
    {
        $types = $restaurant->guest_paging_order_types;

        return is_array($types) && $types !== [] ? array_values($types) : self::DEFAULT_ORDER_TYPES;
    }

    /**
     * BR-2: the flag is on, the type is paged, and this is not a round of a
     * seated table (served to the table, never collected).
     */
    public function isEligible(Restaurant $restaurant, ?string $orderType, bool $tableVisitRound = false): bool
    {
        if ($tableVisitRound || ! $restaurant->hasFeature('guest_paging')) {
            return false;
        }

        return in_array((string) $orderType, $this->pagedOrderTypes($restaurant), true);
    }

    /** BR-3: 40 alphanumerics, unique across every tenant (the URL carries no slug check). */
    public static function generateToken(): string
    {
        do {
            $token = Str::random(40);
        } while (Order::withoutGlobalScopes()->where('pickup_token', $token)->exists());

        return $token;
    }

    /**
     * Move a paged order forward (BR-1, BR-6, BR-8, BR-9, BR-10). Runs under
     * the order's row lock so the till and the tablet cannot race each other.
     *
     * Never throws for a lifecycle reason: the caller reads `reason` and
     * decides (the dashboard answers 422 on `backwards`; the POS endpoint
     * answers 200 `applied:false`, so its outbox never quarantines).
     *
     * @return array{applied: bool, reason: 'ok'|'noop'|'backwards'|'not_paged'|'cancelled', order: Order}
     */
    public function transition(
        Order $order,
        PickupStatus $to,
        string $source,
        ?User $by = null,
        ?CarbonInterface $at = null,
    ): array {
        return DB::transaction(function () use ($order, $to, $source, $by, $at) {
            // Re-read under lock, inside the caller's tenant: the order was
            // already resolved through the tenant scope (or the device's
            // restaurant), so the key alone is safe here.
            $locked = Order::withoutGlobalScopes()
                ->whereKey($order->getKey())
                ->where('restaurant_id', $order->restaurant_id)
                ->lockForUpdate()
                ->firstOrFail();

            $from = $locked->pickup_status;
            if ($from === null) {
                return ['applied' => false, 'reason' => 'not_paged', 'order' => $locked];
            }
            // D-6: a cancelled order is never paged forward — nobody should be
            // told "your order is ready" for food that is not coming.
            if ($locked->status === OrderStatus::CANCELLED) {
                return ['applied' => false, 'reason' => 'cancelled', 'order' => $locked];
            }
            if ($from === $to) {
                return ['applied' => false, 'reason' => 'noop', 'order' => $locked];
            }
            if (! $from->canTransitionTo($to)) {
                return ['applied' => false, 'reason' => 'backwards', 'order' => $locked];
            }

            $stamp = $this->clamp($locked, $at);
            $attrs = ['pickup_status' => $to->value];

            if ($to === PickupStatus::READY) {
                $attrs['ready_at'] = $stamp;
                $attrs['ready_by'] = $by?->id;
                $attrs['ready_source'] = $source;
            }

            if ($to === PickupStatus::PICKED_UP) {
                $attrs['picked_up_at'] = $stamp;

                // BR-8: a QR order the diner just collected is complete in the
                // platform's own lifecycle too — the review prompt keys on it.
                // Through canTransitionTo, never around it; POS sales are
                // already COMPLETED by PosOrderService::completeIfSettled.
                if ($locked->status === OrderStatus::NEW
                    && $locked->status->canTransitionTo(OrderStatus::COMPLETED)) {
                    $attrs['status'] = OrderStatus::COMPLETED->value;
                    $this->markNewOrderAlertRead($locked);
                }
            }

            $locked->forceFill($attrs)->save();

            if ($to === PickupStatus::READY) {
                // After the response, like every other push: the diner's alert
                // must never delay or fail the staff action.
                app()->terminating(fn () => $this->pushReady($locked));
            }

            return ['applied' => true, 'reason' => 'ok', 'order' => $locked];
        });
    }

    /** BR-7: READY, unacknowledged, and the counter has waited long enough to shout. */
    public function isCallOut(Order $order, ?CarbonInterface $now = null): bool
    {
        if ($order->pickup_status !== PickupStatus::READY || $order->acknowledged_at !== null || $order->ready_at === null) {
            return false;
        }

        $minutes = (int) config('platform.guest_paging.call_out_minutes', 3);

        return $order->ready_at->lte(($now ?? Carbon::now())->copy()->subMinutes($minutes));
    }

    /**
     * BR-9: a till's own clock may be off, so its event time is kept within
     * [the order's creation, now]. The dashboard passes no time at all.
     */
    private function clamp(Order $order, ?CarbonInterface $at): Carbon
    {
        $now = Carbon::now();
        $stamp = $at ? Carbon::instance($at) : $now;

        if ($stamp->gt($now)) {
            $stamp = $now;
        }
        if ($order->created_at !== null && $stamp->lt($order->created_at)) {
            $stamp = $order->created_at->copy();
        }

        return $stamp;
    }

    /** Same courtesy Dashboard\OrderController::updateStatus pays when an order leaves NEW. */
    private function markNewOrderAlertRead(Order $order): void
    {
        Notification::withoutGlobalScopes()
            ->where('restaurant_id', $order->restaurant_id)
            ->where('type', 'order.created')
            ->where('data->order_id', (string) $order->id)
            ->whereNull('read_at')
            ->update(['read_at' => Carbon::now()]);
    }

    /**
     * The diner's web-push alert. Stage S8 wires PushService here; until then
     * the call site exists and does nothing, so READY already has the right
     * shape for the rest of the feature.
     */
    private function pushReady(Order $order): void
    {
        if ($order->pickup_push_token === null) {
            return;
        }
        // S8: PushService::toTokens([$order->pickup_push_token], ...).
    }
}

<?php

namespace App\Services;

use App\Enums\PickupStatus;
use App\Models\Order;
use App\Models\Restaurant;
use App\Support\Digits;
use Illuminate\Support\Facades\DB;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): finds the order a
 * client means from the number printed on their slip.
 *
 * The slip carries the invoice number, `MAIN-2026-000042`, which the platform
 * counts up by one per order. The client types the digits at its end ("42"), or
 * the whole number as printed. We look only through THIS restaurant's till
 * orders sold in the last few hours, so a short number is enough and another
 * restaurant's orders are never in reach (BR-3).
 */
class PagerLookupService
{
    public const FOUND = 'found';

    public const NOT_FOUND = 'not_found';

    public const AMBIGUOUS = 'ambiguous';

    /** More than any counter sells in the window; keeps the scan bounded. */
    private const MAX_CANDIDATES = 2000;

    public function __construct(private readonly GuestPagingService $paging) {}

    /**
     * @return array{status: 'found'|'not_found'|'ambiguous', order: Order|null}
     */
    public function find(Restaurant $restaurant, string $input): array
    {
        $raw = Digits::latin(trim($input));
        if ($raw === '' || strlen($raw) > 40) {
            return ['status' => self::NOT_FOUND, 'order' => null];
        }

        $tail = ctype_digit($raw) ? (strlen($raw) <= 9 ? (int) $raw : null) : null;
        $full = ctype_digit($raw) ? null : self::squash($raw);
        if ($tail === null && $full === null) {
            return ['status' => self::NOT_FOUND, 'order' => null];
        }

        $matches = [];
        foreach ($this->candidates($restaurant) as $order) {
            $invoice = (string) $order->invoice_number;
            $hit = $tail !== null
                ? self::tailOf($invoice) === $tail
                : self::squash($invoice) === $full;

            if ($hit && $this->paging->isEligible($restaurant, $order->order_type)) {
                $matches[] = $order;
            }
        }

        if ($matches === []) {
            return ['status' => self::NOT_FOUND, 'order' => null];
        }
        if (count($matches) > 1) {
            return ['status' => self::AMBIGUOUS, 'order' => null];
        }

        return ['status' => self::FOUND, 'order' => $this->page($matches[0])];
    }

    /** This restaurant's till orders sold inside the window, newest first. */
    private function candidates(Restaurant $restaurant)
    {
        return Order::withoutGlobalScopes()
            ->where('restaurant_id', $restaurant->id)
            ->where('channel', 'pos')
            ->whereNotNull('invoice_number')
            ->where('created_at', '>=', now()->subHours(max(1, (int) config('platform.guest_paging.lookup_window_hours', 12))))
            ->orderByDesc('id')
            ->limit(self::MAX_CANDIDATES)
            ->get();
    }

    /**
     * Make the order pageable if it is not yet: a till order has no tracking
     * token, so give it one and start it preparing, exactly as a QR-menu order
     * gets at creation. An order that already has a token is returned as it is.
     * Idempotent, and safe if two phones look it up at once (row lock).
     */
    private function page(Order $order): Order
    {
        return DB::transaction(function () use ($order) {
            $locked = Order::withoutGlobalScopes()
                ->whereKey($order->getKey())
                ->where('restaurant_id', $order->restaurant_id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($locked->pickup_token === null) {
                $locked->forceFill([
                    'pickup_token' => GuestPagingService::generateToken(),
                    'pickup_status' => PickupStatus::PREPARING->value,
                    // The number as the client reads it, without leading zeros.
                    'pickup_display_ref' => $locked->pickup_display_ref
                        ?? (string) (self::tailOf((string) $locked->invoice_number) ?? $locked->invoice_number),
                ])->save();
            }

            return $locked;
        });
    }

    /** The digits at the very end of an invoice number, as an integer. */
    public static function tailOf(string $invoice): ?int
    {
        return preg_match('/(\d+)\D*$/', $invoice, $m) === 1 ? (int) $m[1] : null;
    }

    /** Compare invoice numbers ignoring case, spaces and dashes. */
    private static function squash(string $value): string
    {
        return strtoupper(preg_replace('/[\s\-_]+/', '', $value));
    }
}

<?php

namespace App\Services;

use App\Enums\PickupStatus;
use App\Models\Order;
use App\Models\PagerSession;
use App\Models\Restaurant;
use App\Support\Digits;
use Illuminate\Database\UniqueConstraintViolationException;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use RuntimeException;
use Throwable;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr).
 *
 * A phone that scans the restaurant's one standing QR gets a pairing session:
 * a short numeric CODE the client reads out, and a long SECRET the phone keeps.
 * The cashier types the code with an order; bind() ties the session to that
 * order, frees the code, and from then on the phone is handed the order's
 * tracking token (the existing order-number page does the rest).
 *
 * Every query names the restaurant: this runs on public requests (no tenant
 * context) and on a till's request (the device's restaurant), and a code from
 * one restaurant must never resolve in another (BR-4).
 */
class PagerSessionService
{
    public const PAIRED = 'paired';

    public const NOT_FOUND = 'not_found';

    public const EXPIRED = 'expired';

    public const ALREADY_USED = 'already_used';

    public const NOT_ELIGIBLE = 'not_eligible';

    public function __construct(private readonly GuestPagingService $paging) {}

    private function digits(): int
    {
        return max(3, min(8, (int) config('platform.guest_paging.pairing_code_digits', 4)));
    }

    private function ttlMinutes(): int
    {
        return max(1, (int) config('platform.guest_paging.pairing_ttl_minutes', 30));
    }

    public static function hashSecret(string $secret): string
    {
        return hash('sha256', $secret);
    }

    /** Latin digits only, trimmed; anything else cannot be a code. */
    public static function normalizeCode(?string $code): ?string
    {
        $code = Digits::latin(trim((string) $code));

        return preg_match('/^\d{3,8}$/', $code) === 1 ? $code : null;
    }

    /**
     * Resume the phone's session when it is still good, else open a new one.
     *
     * @return array{session: PagerSession, secret: string|null} `secret` is set
     *                                                           only for a NEW session: it is shown to the phone once.
     */
    public function start(Restaurant $restaurant, ?string $secret): array
    {
        if ($secret !== null && $secret !== '') {
            $existing = $this->find($restaurant, $secret);
            if ($existing !== null && ! $existing->isExpired()) {
                return ['session' => $existing, 'secret' => null];
            }
        }

        // Free the numbers of dead codes before picking one.
        PagerSession::query()
            ->where('restaurant_id', $restaurant->id)
            ->whereNull('bound_at')
            ->where('expires_at', '<', now())
            ->delete();

        $digits = $this->digits();
        $newSecret = Str::random(40);

        for ($attempt = 0; $attempt < 25; $attempt++) {
            $session = new PagerSession;
            $session->forceFill([
                'restaurant_id' => $restaurant->id,
                'code' => (string) random_int(10 ** ($digits - 1), (10 ** $digits) - 1),
                'secret_hash' => self::hashSecret($newSecret),
                'expires_at' => now()->addMinutes($this->ttlMinutes()),
            ]);

            try {
                $session->save();

                return ['session' => $session, 'secret' => $newSecret];
            } catch (UniqueConstraintViolationException) {
                // Another open code has that number: try another.
            }
        }

        throw new RuntimeException('No free pairing code.');
    }

    public function find(Restaurant $restaurant, string $secret): ?PagerSession
    {
        return PagerSession::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('secret_hash', self::hashSecret($secret))
            ->first();
    }

    /** Is this code open right now for this restaurant? (The till's quick check.) */
    public function peek(Restaurant $restaurant, ?string $code): bool
    {
        $code = self::normalizeCode($code);
        if ($code === null || ! $restaurant->hasFeature('guest_paging')) {
            return false;
        }

        return PagerSession::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('code', $code)
            ->whereNull('bound_at')
            ->where('expires_at', '>', now())
            ->exists();
    }

    /**
     * Tie an open session to an order. Never throws: the sale has already
     * happened, and a bad code must not change its outcome (BR-7). The
     * caller reports the returned status, nothing more.
     *
     * Idempotent: the till retries, and a replayed order is bound again, so an
     * order that is already paired answers `paired`.
     */
    public function bind(Restaurant $restaurant, Order $order, ?string $rawCode): string
    {
        try {
            return DB::transaction(fn () => $this->bindLocked($restaurant, $order, $rawCode));
        } catch (Throwable $e) {
            Log::warning('Pager bind failed', ['order' => $order->id, 'error' => $e->getMessage()]);

            return self::NOT_FOUND;
        }
    }

    private function bindLocked(Restaurant $restaurant, Order $order, ?string $rawCode): string
    {
        // The order must be this restaurant's own: a till of restaurant B can
        // never pair to an order of A, even if it somehow named it.
        if ((int) $order->restaurant_id !== (int) $restaurant->id) {
            return self::NOT_FOUND;
        }

        // Already paired (a retry or a replay): nothing to do.
        if (PagerSession::query()->where('order_id', $order->id)->exists()) {
            return self::PAIRED;
        }

        $code = self::normalizeCode($rawCode);
        if ($code === null) {
            return self::NOT_FOUND;
        }

        $session = PagerSession::query()
            ->where('restaurant_id', $restaurant->id)
            ->where('code', $code)
            ->lockForUpdate()
            ->first();

        if ($session === null) {
            return self::NOT_FOUND;
        }
        if ($session->isBound()) {
            return self::ALREADY_USED;
        }
        if ($session->isExpired()) {
            return self::EXPIRED;
        }

        // Paged orders only, and never a round of a seated table (BR-2).
        if (! $this->paging->isEligible($restaurant, $order->order_type)) {
            return self::NOT_ELIGIBLE;
        }

        // A till order has no tracking token yet: give it one and start it
        // preparing, as a QR-menu order gets at creation. The reference the
        // client sees is the number on the slip (the invoice number), not the
        // internal id.
        if ($order->pickup_token === null) {
            $order->forceFill([
                'pickup_token' => GuestPagingService::generateToken(),
                'pickup_status' => PickupStatus::PREPARING->value,
                'pickup_display_ref' => $order->pickup_display_ref
                    ?? ($order->invoice_number !== null ? (string) $order->invoice_number : null),
            ])->save();
        }

        $session->forceFill([
            'code' => null, // the number is free for the next client
            'order_id' => $order->id,
            'bound_at' => now(),
        ])->save();

        return self::PAIRED;
    }

    /** Delete dead sessions. Returns how many went. */
    public function prune(): int
    {
        $ttl = (int) config('platform.guest_paging.tracking_ttl_hours', 48);

        $expired = PagerSession::query()
            ->whereNull('bound_at')
            ->where('expires_at', '<', now()->subHour())
            ->delete();

        $old = PagerSession::query()
            ->whereNotNull('bound_at')
            ->where('bound_at', '<', now()->subHours($ttl))
            ->delete();

        return $expired + $old;
    }
}

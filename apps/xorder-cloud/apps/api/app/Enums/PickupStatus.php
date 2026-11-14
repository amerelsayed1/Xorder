<?php

namespace App\Enums;

/**
 * Guest paging: where a counter order is on its way to the diner's hands.
 * Lives beside OrderStatus (NEW/COMPLETED/CANCELLED), never inside it — the
 * platform lifecycle enum is frozen by contract (BACKEND_TO_POS §010).
 *
 * Null on the order means "not a paged order". Once set it only moves forward:
 * a delayed till event can never undo what the counter tablet already did.
 */
enum PickupStatus: string
{
    case PREPARING = 'PREPARING';
    case READY = 'READY';
    case PICKED_UP = 'PICKED_UP';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }

    /**
     * Monotonic: PREPARING → READY → PICKED_UP, and PREPARING → PICKED_UP for
     * an order handed over without anyone pressing Ready. Same → same is a
     * harmless no-op (an idempotent replay); backwards is never allowed.
     */
    public function canTransitionTo(self $to): bool
    {
        if ($this === $to) {
            return true;
        }

        return match ($this) {
            self::PREPARING => in_array($to, [self::READY, self::PICKED_UP], true),
            self::READY => $to === self::PICKED_UP,
            self::PICKED_UP => false,
        };
    }
}

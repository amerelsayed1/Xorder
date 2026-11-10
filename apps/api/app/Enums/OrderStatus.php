<?php

namespace App\Enums;

enum OrderStatus: string
{
    /**
     * A WhatsApp order waiting for an employee to accept or reject it. Not yet
     * a real order: never in the kitchen queue, the "new" badge, sales or
     * reports. Only creation sets it; nothing moves back to it.
     */
    case PENDING = 'PENDING';
    case NEW = 'NEW';
    case COMPLETED = 'COMPLETED';
    case CANCELLED = 'CANCELLED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }

    /**
     * Whether a status change is allowed. Staff may correct a mistake between
     * the two terminal states (COMPLETED ↔ CANCELLED), and re-applying the same
     * status is a harmless no-op — but an order can never be reopened back to
     * NEW once it has been acted on, which would corrupt the "new orders" badge
     * and order-history reporting.
     */
    public function canTransitionTo(self $to): bool
    {
        if ($this === $to) {
            return true;
        }

        return match ($this) {
            self::PENDING => in_array($to, [self::NEW, self::CANCELLED], true),
            self::NEW => in_array($to, [self::COMPLETED, self::CANCELLED], true),
            self::COMPLETED, self::CANCELLED => ! in_array($to, [self::NEW, self::PENDING], true),
        };
    }
}

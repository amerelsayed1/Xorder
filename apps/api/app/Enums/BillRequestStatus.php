<?php

namespace App\Enums;

enum BillRequestStatus: string
{
    case REQUESTED = 'REQUESTED';
    case SEEN = 'SEEN';
    case IN_PROGRESS = 'IN_PROGRESS';
    case COMPLETED = 'COMPLETED';
    case CANCELLED = 'CANCELLED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }

    /** Still on the live board — not yet completed or cancelled. */
    public function isOpen(): bool
    {
        return in_array($this, [self::REQUESTED, self::SEEN, self::IN_PROGRESS], true);
    }
}

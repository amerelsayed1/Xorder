<?php

namespace App\Enums;

enum LeadStatus: string
{
    case NEW = 'NEW';
    case CONTACTED = 'CONTACTED';
    case DEMO_SCHEDULED = 'DEMO_SCHEDULED';
    case PROPOSAL_SENT = 'PROPOSAL_SENT';
    case WON = 'WON';
    case LOST = 'LOST';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }
}

<?php

namespace App\Enums;

enum ReviewStatus: string
{
    case NEW = 'NEW';
    case IN_REVIEW = 'IN_REVIEW';
    case CONTACTED = 'CONTACTED';
    case RESOLVED = 'RESOLVED';
    case ARCHIVED = 'ARCHIVED';

    /** @return list<string> */
    public static function values(): array
    {
        return array_map(fn (self $c) => $c->value, self::cases());
    }
}

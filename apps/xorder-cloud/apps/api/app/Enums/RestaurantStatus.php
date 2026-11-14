<?php

namespace App\Enums;

enum RestaurantStatus: string
{
    case ACTIVE = 'ACTIVE';
    case SUSPENDED = 'SUSPENDED';
    case ARCHIVED = 'ARCHIVED';

    /** Whether the public menu should be visible for this status. */
    public function isPubliclyVisible(): bool
    {
        return $this === self::ACTIVE;
    }
}

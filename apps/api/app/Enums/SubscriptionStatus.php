<?php

namespace App\Enums;

enum SubscriptionStatus: string
{
    case TRIAL = 'TRIAL';
    case ACTIVE = 'ACTIVE';
    case EXPIRED = 'EXPIRED';
    case SUSPENDED = 'SUSPENDED';

    /** Subscription states that allow the restaurant admin to mutate data. */
    public function allowsDashboardWrites(): bool
    {
        return match ($this) {
            self::TRIAL, self::ACTIVE => true,
            self::EXPIRED, self::SUSPENDED => false,
        };
    }
}

<?php

namespace App\Enums;

enum RoleEnum: string
{
    case SUPER_ADMIN = 'SUPER_ADMIN';
    case RESTAURANT_ADMIN = 'RESTAURANT_ADMIN';

    public function isSuperAdmin(): bool
    {
        return $this === self::SUPER_ADMIN;
    }

    public function isRestaurantAdmin(): bool
    {
        return $this === self::RESTAURANT_ADMIN;
    }
}

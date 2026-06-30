<?php

namespace App\Policies;

use App\Models\Restaurant;
use App\Models\User;

class RestaurantPolicy
{
    /** Super Admin bypasses all checks. */
    public function before(User $user, string $ability): ?bool
    {
        return $user->isSuperAdmin() ? true : null;
    }

    /** A restaurant admin may view/update only their own restaurant. */
    public function view(User $user, Restaurant $restaurant): bool
    {
        return $user->restaurant_id === $restaurant->id;
    }

    public function update(User $user, Restaurant $restaurant): bool
    {
        return $user->restaurant_id === $restaurant->id;
    }

    /** Only Super Admin (handled by before) may create restaurants. */
    public function create(User $user): bool
    {
        return false;
    }

    public function manageSubscription(User $user, Restaurant $restaurant): bool
    {
        return false; // Super Admin only (via before()).
    }
}

<?php

namespace App\Policies;

use App\Models\MenuItem;
use App\Models\User;

class MenuItemPolicy
{
    private function owns(User $user, MenuItem $item): bool
    {
        return $user->isRestaurantAdmin()
            && $user->restaurant_id === $item->restaurant_id;
    }

    public function view(User $user, MenuItem $item): bool
    {
        return $this->owns($user, $item);
    }

    public function update(User $user, MenuItem $item): bool
    {
        return $this->owns($user, $item);
    }

    public function delete(User $user, MenuItem $item): bool
    {
        return $this->owns($user, $item);
    }
}

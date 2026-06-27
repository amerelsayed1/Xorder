<?php

namespace App\Policies;

use App\Models\Category;
use App\Models\User;

class CategoryPolicy
{
    private function owns(User $user, Category $category): bool
    {
        return $user->isRestaurantAdmin()
            && $user->restaurant_id === $category->restaurant_id;
    }

    public function view(User $user, Category $category): bool
    {
        return $this->owns($user, $category);
    }

    public function update(User $user, Category $category): bool
    {
        return $this->owns($user, $category);
    }

    public function delete(User $user, Category $category): bool
    {
        return $this->owns($user, $category);
    }
}

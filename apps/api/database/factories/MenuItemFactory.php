<?php

namespace Database\Factories;

use App\Models\Category;
use App\Models\MenuItem;
use App\Models\Restaurant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<MenuItem>
 */
class MenuItemFactory extends Factory
{
    public function definition(): array
    {
        return [
            'restaurant_id' => Restaurant::factory(),
            'category_id' => Category::factory(),
            'name_en' => fake()->unique()->words(2, true),
            'name_ar' => 'صنف ' . fake()->unique()->word(),
            'description_en' => fake()->sentence(),
            'price' => fake()->randomFloat(2, 5, 200),
            'discounted_price' => null,
            'is_available' => true,
            'is_featured' => false,
            'display_order' => 0,
        ];
    }

    public function unavailable(): static
    {
        return $this->state(fn () => ['is_available' => false]);
    }

    public function featured(): static
    {
        return $this->state(fn () => ['is_featured' => true]);
    }
}

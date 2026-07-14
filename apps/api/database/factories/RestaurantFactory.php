<?php

namespace Database\Factories;

use App\Enums\LanguageEnum;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Restaurant>
 */
class RestaurantFactory extends Factory
{
    public function definition(): array
    {
        $nameEn = fake()->unique()->company();

        return [
            'name_en' => $nameEn,
            'name_ar' => 'مطعم '.fake()->unique()->word(),
            'slug' => Str::slug($nameEn).'-'.fake()->unique()->numberBetween(100, 9999),
            'description_en' => fake()->sentence(),
            'description_ar' => 'وصف المطعم',
            'phone' => '+2010'.fake()->numerify('########'),
            'whatsapp_number' => '+2010'.fake()->numerify('########'),
            'address' => fake()->address(),
            'brand_color' => fake()->hexColor(),
            'default_language' => LanguageEnum::AR,
            'status' => RestaurantStatus::ACTIVE,
            'subscription_status' => SubscriptionStatus::TRIAL,
        ];
    }

    public function suspended(): static
    {
        return $this->state(fn () => ['status' => RestaurantStatus::SUSPENDED]);
    }

    public function archived(): static
    {
        return $this->state(fn () => ['status' => RestaurantStatus::ARCHIVED]);
    }
}

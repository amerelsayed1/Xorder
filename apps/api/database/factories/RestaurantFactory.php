<?php

namespace Database\Factories;

use App\Enums\Feature;
use App\Enums\LanguageEnum;
use App\Enums\OrderingMode;
use App\Enums\RestaurantStatus;
use App\Enums\SubscriptionStatus;
use App\Models\Restaurant;
use App\Services\RestaurantFeatureService;
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
            'ordering_mode' => OrderingMode::WHATSAPP,
            'status' => RestaurantStatus::ACTIVE,
            'subscription_status' => SubscriptionStatus::TRIAL,
        ];
    }

    /**
     * Grant the ordering entitlements a normally-provisioned client has, so the
     * public menu accepts system orders. Both channels are enabled, and the
     * ordering_mode is pinned to SYSTEM so the order pipeline actually persists
     * records — since ordering availability is decided by the plan, tests that
     * place orders opt in with this state.
     */
    public function withOrdering(): static
    {
        return $this->state(fn () => ['ordering_mode' => OrderingMode::SYSTEM])
            ->afterCreating(function (Restaurant $restaurant) {
                app(RestaurantFeatureService::class)->apply(
                    $restaurant,
                    array_merge(Feature::defaultSet(), ['system_ordering' => true]),
                );
            });
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

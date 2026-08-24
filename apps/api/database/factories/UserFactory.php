<?php

namespace Database\Factories;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

/**
 * @extends Factory<User>
 */
class UserFactory extends Factory
{
    /**
     * The current password being used by the factory.
     */
    protected static ?string $password;

    /**
     * Define the model's default state.
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'name' => fake()->name(),
            'username' => fake()->unique()->userName(),
            'email' => fake()->unique()->safeEmail(),
            'email_verified_at' => now(),
            'password' => static::$password ??= Hash::make('password'),
            'role' => RoleEnum::RESTAURANT_ADMIN,
            // Owners and platform users carry no custom role; set explicitly so
            // freshly-made models have the attribute (strict Eloquent mode
            // throws on reading one that was never retrieved).
            'role_id' => null,
            'restaurant_id' => null,
            'status' => UserStatus::ACTIVE,
            'remember_token' => Str::random(10),
        ];
    }

    public function superAdmin(): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => RoleEnum::SUPER_ADMIN,
            'restaurant_id' => null,
        ]);
    }

    public function restaurantAdmin(int $restaurantId): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => RoleEnum::RESTAURANT_ADMIN,
            'role_id' => null,
            'restaurant_id' => $restaurantId,
        ]);
    }

    /** A staff account inside a restaurant, holding one custom Role. */
    public function staff(int $restaurantId, int $roleId): static
    {
        return $this->state(fn (array $attributes) => [
            'role' => RoleEnum::RESTAURANT_STAFF,
            'role_id' => $roleId,
            'restaurant_id' => $restaurantId,
        ]);
    }

    /**
     * Indicate that the model's email address should be unverified.
     */
    public function unverified(): static
    {
        return $this->state(fn (array $attributes) => [
            'email_verified_at' => null,
        ]);
    }
}

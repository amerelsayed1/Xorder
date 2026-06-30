<?php

namespace App\Services;

use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\Restaurant;
use App\Models\User;
use App\Notifications\RestaurantAdminCredentials;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

class RestaurantProvisioningService
{
    public function __construct(private readonly SlugService $slugs)
    {
    }

    /**
     * Create a restaurant and its first Restaurant Admin in a single
     * transaction. If no password is supplied, a strong one is generated and
     * returned (and emailed) so the Super Admin can hand it over.
     *
     * @param  array<string,mixed>  $restaurantData
     * @return array{restaurant: Restaurant, admin: User, generated_password: ?string}
     */
    public function provision(array $restaurantData, array $adminData): array
    {
        $generatedPassword = null;
        $plainPassword = $adminData['password'] ?? null;

        if (empty($plainPassword)) {
            $generatedPassword = $this->generatePassword();
            $plainPassword = $generatedPassword;
        }

        // Guarantee a unique slug even under a race (DB unique index is the
        // ultimate guard; this avoids a noisy 500 in the common case).
        $restaurantData['slug'] = $this->slugs->unique($restaurantData['slug']);

        [$restaurant, $admin] = DB::transaction(function () use ($restaurantData, $adminData, $plainPassword) {
            $restaurant = Restaurant::create($restaurantData);

            $admin = User::create([
                'name' => $adminData['name'],
                'email' => $adminData['email'],
                'password' => Hash::make($plainPassword),
                'role' => RoleEnum::RESTAURANT_ADMIN,
                'restaurant_id' => $restaurant->id,
                'status' => UserStatus::ACTIVE,
                'email_verified_at' => now(),
            ]);

            return [$restaurant, $admin];
        });

        // Email the credentials (queued/log driver in dev). Never blocks the request flow.
        $admin->notify(new RestaurantAdminCredentials($restaurant, $plainPassword));

        return [
            'restaurant' => $restaurant->fresh(),
            'admin' => $admin,
            'generated_password' => $generatedPassword,
        ];
    }

    /**
     * Regenerate a Restaurant Admin's password, re-email the credentials, and
     * return the new plaintext once so the Super Admin can hand it over.
     */
    public function resetAdminPassword(User $admin): string
    {
        $password = $this->generatePassword();

        // The 'password' => 'hashed' cast hashes on assignment.
        $admin->update(['password' => $password]);

        $admin->notify(new RestaurantAdminCredentials($admin->restaurant, $password));

        return $password;
    }

    private function generatePassword(): string
    {
        // 16 chars, URL-safe, plenty of entropy.
        return Str::password(16, symbols: false);
    }
}

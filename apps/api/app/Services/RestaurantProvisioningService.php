<?php

namespace App\Services;

use App\Enums\Feature;
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
    public function __construct(
        private readonly SlugService $slugs,
        private readonly RestaurantFeatureService $features,
    ) {}

    /**
     * Create a restaurant and its first Restaurant Admin — and, when supplied,
     * its first branch and feature flags — in a single transaction. If no
     * password is supplied, a strong one is generated and returned (and
     * emailed) so the Super Admin can hand it over.
     *
     * This is the one provisioning core shared by both front doors: the
     * Super Admin creation wizard and self-serve signup. Passing $branchData
     * and $features lets the wizard commit the whole client atomically while
     * signup keeps calling it with sensible defaults.
     *
     * @param  array<string,mixed>  $restaurantData
     * @param  array<string,mixed>  $adminData
     * @param  array<string,mixed>|null  $branchData  First branch, or null to skip (FR-BRANCH-007).
     * @param  array<string,bool>  $features  Requested flag map; [] applies the default set.
     * @return array{restaurant: Restaurant, admin: User, generated_password: ?string}
     */
    public function provision(
        array $restaurantData,
        array $adminData,
        ?array $branchData = null,
        array $features = [],
    ): array {
        $generatedPassword = null;
        $plainPassword = $adminData['password'] ?? null;

        if (empty($plainPassword)) {
            $generatedPassword = $this->generatePassword();
            $plainPassword = $generatedPassword;
        }

        // Guarantee a unique slug even under a race (DB unique index is the
        // ultimate guard; this avoids a noisy 500 in the common case).
        $restaurantData['slug'] = $this->slugs->unique($restaurantData['slug']);

        $featureSet = $features === [] ? Feature::defaultSet() : $features;

        [$restaurant, $admin] = DB::transaction(function () use ($restaurantData, $adminData, $plainPassword, $branchData, $featureSet) {
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

            if ($branchData !== null) {
                // restaurant_id is stamped by the HasMany relation.
                $restaurant->branches()->create($branchData);
            }

            $this->features->apply($restaurant, $featureSet);

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

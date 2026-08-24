<?php

namespace App\Services;

use App\Enums\CurrencyEnum;
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
        private readonly PlanEntitlementService $entitlements,
        private readonly TenantRoleService $roles,
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

        // The Super Admin wizard supplies an explicit username; self-serve
        // signup doesn't, so derive one from the (already-unique) slug.
        if (empty($adminData['username'])) {
            $adminData['username'] = $this->uniqueUsername($restaurantData['slug']);
        }

        // The plan strictly decides features; this only applies when the
        // restaurant has no plan (e.g. self-serve signup) or the plan predates
        // the entitlement set.
        $fallback = $features === [] ? Feature::defaultSet() : $features;

        // Every new restaurant starts on a one-month trial unless the caller
        // supplied explicit subscription dates (e.g. a paid plan from the admin
        // wizard). Server time is the source of truth; addMonth() handles
        // month-end boundaries safely (e.g. Jan 31 → Feb 28/29).
        if (empty($restaurantData['subscription_start_date'])) {
            $restaurantData['subscription_start_date'] = now()->toDateString();
        }
        if (empty($restaurantData['subscription_end_date'])) {
            $restaurantData['subscription_end_date'] = now()->addMonth()->toDateString();
        }

        // Seed a timezone from the billing currency so a new restaurant's
        // "today" turns over at its own midnight from day one. Leaving it null
        // would silently mean UTC, which for a Cairo owner rolls the dashboard
        // over at 3am. The owner can change it in their profile.
        if (empty($restaurantData['timezone'])) {
            $currency = CurrencyEnum::tryFrom((string) ($restaurantData['currency'] ?? ''))
                ?? CurrencyEnum::EGP;

            $restaurantData['timezone'] = $currency->defaultTimezone() ?: config('app.timezone', 'UTC');
        }

        [$restaurant, $admin] = DB::transaction(function () use ($restaurantData, $adminData, $plainPassword, $branchData, $fallback) {
            $restaurant = Restaurant::create($restaurantData);

            // forceCreate: `role` and `restaurant_id` are guarded (non-fillable)
            // so they can only be set here, in trusted provisioning code.
            $admin = User::forceCreate([
                'name' => $adminData['name'],
                'username' => $adminData['username'],
                'email' => $adminData['email'] ?? null,
                'password' => Hash::make($plainPassword),
                'password_changed_at' => now(),
                'role' => RoleEnum::RESTAURANT_ADMIN,
                'role_id' => null,
                'restaurant_id' => $restaurant->id,
                'status' => UserStatus::ACTIVE,
                'email_verified_at' => now(),
            ]);

            // Seed the four system staff roles so the restaurant can start
            // adding people the moment it is created, and can never end up with
            // no role to assign.
            $this->roles->seedSystemRoles($restaurant);

            if ($branchData !== null) {
                // restaurant_id is stamped by the HasMany relation.
                $restaurant->branches()->create($branchData);
            }

            $this->features->apply($restaurant, $this->entitlements->resolvedMapFor($restaurant, $fallback));

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

        // The 'password' => 'hashed' cast hashes on assignment. Stamp
        // password_changed_at so any JWT issued before this reset is rejected
        // by the guard — a compromised admin session cannot outlive the reset.
        $admin->forceFill([
            'password' => $password,
            'password_changed_at' => now(),
        ])->save();

        $admin->notify(new RestaurantAdminCredentials($admin->restaurant, $password));

        return $password;
    }

    private function generatePassword(): string
    {
        // 16 chars, URL-safe, plenty of entropy.
        return Str::password(16, symbols: false);
    }

    /** A login username derived from the slug, suffixed until unique. */
    private function uniqueUsername(string $base): string
    {
        $base = Str::of($base)->lower()->replaceMatches('/[^a-z0-9._-]/', '')->toString();
        if ($base === '') {
            $base = 'owner';
        }

        $username = $base;
        $i = 1;
        while (User::where('username', $username)->exists()) {
            $username = $base.(++$i);
        }

        return $username;
    }
}

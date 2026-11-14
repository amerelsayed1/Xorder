<?php

namespace App\Services;

use App\Enums\CurrencyEnum;
use App\Enums\Feature;
use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\Plan;
use App\Models\PosLicence;
use App\Models\Restaurant;
use App\Models\User;
use App\Notifications\RestaurantAdminCredentials;
use Illuminate\Support\Carbon;
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
        private readonly LicenceIssuer $licences,
    ) {}

    /**
     * Create a restaurant, its first Restaurant Admin and its POS licence —
     * and, when supplied, its first branch and feature flags — in a single
     * transaction. If no password is supplied, a strong one is generated and
     * returned (and emailed) so the Super Admin can hand it over.
     *
     * This is the one provisioning core shared by both front doors: the
     * Super Admin creation wizard and self-serve signup. Passing $branchData
     * and $features lets the wizard commit the whole client atomically while
     * signup keeps calling it with sensible defaults.
     *
     * TENANT = RESTAURANT + LICENCE, and nothing else (owner decision,
     * 2026-09-05). The licence is minted inside the same transaction, so a
     * signing failure rolls the restaurant back rather than leaving a client
     * that exists but can never license a till. NO TERMINAL IS CREATED HERE,
     * ever — a terminal is an explicit later action (PosProvisioningService),
     * and a tenant with zero terminals is a valid, expected state.
     *
     * @param  array<string,mixed>  $restaurantData
     * @param  array<string,mixed>  $adminData
     * @param  array<string,mixed>|null  $branchData  First branch, or null to skip (FR-BRANCH-007).
     * @param  array<string,bool>  $features  Requested flag map; [] applies the default set.
     * @param  array<string,mixed>  $licenceData  Licence overrides; [] derives everything from the plan.
     * @param  User|null  $actor  Platform staff issuing the licence; null for self-serve signup.
     * @return array{restaurant: Restaurant, admin: User, generated_password: ?string, licence: PosLicence, licence_key: string}
     */
    public function provision(
        array $restaurantData,
        array $adminData,
        ?array $branchData = null,
        array $features = [],
        array $licenceData = [],
        ?User $actor = null,
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

        [$restaurant, $admin, $licence, $licenceKey] = DB::transaction(function () use ($restaurantData, $adminData, $plainPassword, $branchData, $fallback, $licenceData, $actor) {
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

            $resolved = $this->entitlements->resolvedMapFor($restaurant, $fallback);
            $this->features->apply($restaurant, $resolved);

            // Step 3 of the flow: the licence. Inside the transaction, so a
            // missing signing key or a bad term aborts the whole tenant
            // instead of committing one without the other. LicenceIssuer's own
            // DB::transaction nests as a savepoint and rolls back with us.
            ['licence' => $licence, 'key' => $licenceKey] = $this->licences->issue(
                $restaurant,
                $this->licenceAttributes($restaurant, $resolved, $licenceData),
                $actor,
            );

            return [$restaurant, $admin, $licence, $licenceKey];
        });

        // Email the credentials (queued/log driver in dev). Never blocks the request flow.
        $admin->notify(new RestaurantAdminCredentials($restaurant, $plainPassword));

        return [
            'restaurant' => $restaurant->fresh(),
            'admin' => $admin,
            'generated_password' => $generatedPassword,
            'licence' => $licence,
            // Returned exactly once — the row keeps only the HMAC. The caller
            // owns showing it to the operator before it is gone for good.
            'licence_key' => $licenceKey,
        ];
    }

    /**
     * The licence a brand-new tenant is born with.
     *
     * Every field falls back to something the tenant already decided, so the
     * creation form never has to ask twice: the term follows the subscription
     * dates, the seat count follows the plan, and the licensed features follow
     * the same resolved entitlement map the restaurant itself was given. An
     * explicit override always wins — the Super Admin wizard can sell a
     * bespoke term without touching the plan.
     *
     * @param  array<string,bool>  $resolvedFeatures
     * @param  array<string,mixed>  $overrides
     * @return array<string,mixed>
     */
    private function licenceAttributes(Restaurant $restaurant, array $resolvedFeatures, array $overrides): array
    {
        $plan = $restaurant->subscription_plan
            ? Plan::where('name', $restaurant->subscription_plan)->first()
            : null;

        $defaults = (array) config('licence.defaults', []);

        $issuedAt = Carbon::parse($overrides['issued_at'] ?? $restaurant->subscription_start_date ?? now());
        $expiresAt = Carbon::parse($overrides['expires_at'] ?? $restaurant->subscription_end_date ?? now()->addMonth());

        // A same-day term signs a licence that is already expired. Push it to
        // the end of the day so a one-day trial is a day, not zero seconds.
        if ($expiresAt->lessThanOrEqualTo($issuedAt)) {
            $expiresAt = $issuedAt->copy()->addMonth();
        }

        // Licensed features mirror the entitlement map: only the keys actually
        // switched on. An empty map licenses nothing extra, which is honest.
        $features = $overrides['features']
            ?? array_keys(array_filter($resolvedFeatures));

        return [
            'plan_id' => $overrides['plan_id'] ?? $plan?->id,
            'issued_at' => $issuedAt,
            'expires_at' => $expiresAt,
            'grace_days' => $overrides['grace_days'] ?? $defaults['grace_days'] ?? 14,
            'warn_days' => $overrides['warn_days'] ?? $defaults['warn_days'] ?? 30,
            // Seats sold, not terminals created. Nothing here creates a
            // terminal; this is only the ceiling the first one will check.
            'max_terminals' => $overrides['max_terminals'] ?? $plan?->max_terminals ?? $defaults['max_terminals'] ?? 1,
            'max_offline_days' => $overrides['max_offline_days'] ?? null,
            'features' => array_values($features),
            // Never empty: an empty modes[] parses to an empty set on the till
            // and every deployment mode then fails to license.
            'modes' => array_values($overrides['modes'] ?? ['cloud']),
            // Empty = every branch of the tenant, including branches created
            // long after this licence was signed.
            'branch_ids' => array_values($overrides['branch_ids'] ?? []),
            'fingerprints' => array_values($overrides['fingerprints'] ?? []),
            'notes' => $overrides['notes'] ?? null,
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

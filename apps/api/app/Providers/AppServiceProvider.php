<?php

namespace App\Providers;

use App\Enums\Capability;
use App\Enums\RoleEnum;
use App\Enums\TenantCapability;
use App\Enums\UserStatus;
use App\Models\User;
use App\Services\PosConfigVersion;
use App\Support\Jwt;
use App\Support\LicenceKey;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\ServiceProvider;
use Illuminate\Support\Str;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        $this->enforceStrictModels();
        $this->registerJwtGuard();
        $this->registerRateLimiters();
        $this->registerGates();
        $this->registerPasswordResetUrl();

        // POS-BE-025: bundle-shaped model writes bump the tenant's
        // pos_config_version so tills know to refresh. One service owns the
        // increment; the hooks live there too.
        PosConfigVersion::registerHooks();
    }

    /**
     * Make Eloquent's three quiet failure modes loud everywhere except
     * production: lazy loading, silently discarded attributes, and reads of
     * attributes that were never selected.
     *
     * The one that earns its place is lazy loading. The public menu builds a
     * whole restaurant — every category, item and option group — in ten
     * queries, and stays that way only because the eager loads are deliberate
     * (see PublicMenuService's auto-group merge). Nothing enforced that: one
     * lazy relation added to a resource would turn ten queries into hundreds,
     * and the only symptom would be a menu that got slower as tenants grew.
     * Enabling this immediately surfaced exactly that in the bulk table-QR
     * download, which was issuing one extra query per QR.
     *
     * Deliberately off in production: these throw, and a surprise exception in
     * front of a diner is worse than a slow query. The point is to fail in CI
     * before it ever reaches them. One consequence worth knowing — a mass
     * assignment that production would silently drop now raises locally, which
     * is why SecurityHardeningTest lifts the second flag where it asserts that
     * production behaviour on purpose.
     */
    private function enforceStrictModels(): void
    {
        Model::shouldBeStrict(! $this->app->isProduction());
    }

    /**
     * Point the framework's password-reset notification at the SPA reset page.
     *
     * Laravel's default ResetPassword notification builds its link from a
     * `password.reset` named route, which this API does not define — without
     * this callback sendResetLink() throws RouteNotFoundException for every
     * real account, which both breaks reset entirely and leaks user existence
     * (a registered email 500s while an unknown one returns the generic 200).
     *
     * Restaurant admins reset on their own dashboard subdomain; platform staff
     * (no tenant) reset on the super-admin portal host.
     */
    private function registerPasswordResetUrl(): void
    {
        ResetPassword::createUrlUsing(function (User $user, string $token): string {
            $query = 'token='.$token.'&email='.urlencode($user->email);

            if ($user->restaurant) {
                return $user->restaurant->dashboardUrl('reset-password').'?'.$query;
            }

            $domain = config('platform.menu_domain');
            if ($domain) {
                $scheme = config('platform.menu_secure', true) ? 'https' : 'http';
                $port = config('platform.menu_port');
                $portPart = $port ? ":{$port}" : '';
                $base = "{$scheme}://{$domain}{$portPart}";
            } else {
                $base = rtrim((string) config('app.url'), '/');
            }

            return $base.'/reset-password?'.$query;
        });
    }

    /**
     * Capability gates backing the `can:<capability>` route middleware on the
     * admin panel. SUPER_ADMIN short-circuits to "allow everything"; every other
     * platform role is granted exactly the capabilities its RoleEnum lists. The
     * matrix lives in RoleEnum::capabilities() (mirrored, UX-only, on the front
     * end in packages/api-client/src/auth.js).
     */
    private function registerGates(): void
    {
        Gate::before(fn (User $user) => $user->role === RoleEnum::SUPER_ADMIN ? true : null);

        foreach (Capability::cases() as $capability) {
            Gate::define(
                $capability->value,
                fn (User $user) => in_array($capability->value, $user->role->capabilities(), true),
            );
        }

        // Tenant-side abilities backing `can:<tenant capability>` on the
        // /api/dashboard routes. These are NOT resolved from a static role
        // matrix: a restaurant builds its own roles, so each user's set comes
        // from the Role assigned to them — with the restaurant owner
        // (RESTAURANT_ADMIN) holding everything, mirroring the SUPER_ADMIN
        // bypass one level down. Values never collide with Capability's.
        foreach (TenantCapability::cases() as $capability) {
            Gate::define(
                $capability->value,
                fn (User $user) => $user->holdsTenantCapability($capability),
            );
        }

        // Derived ability — deliberately NOT a TenantCapability, so it never
        // appears as a checkbox in the role editor. The branch *list* is
        // reference data: every branch-scoped screen (dining areas, tables) has
        // to resolve a branch name and pick a branch when creating. A role with
        // tables.view therefore needs the list without being handed
        // branches.view, which also opens the Wi-Fi presence endpoint.
        Gate::define('branches.list', fn (User $user) => $user->holdsTenantCapability(TenantCapability::BRANCHES_VIEW)
            || $user->holdsTenantCapability(TenantCapability::TABLES_VIEW));

        // The live board reads three resources at once. Rather than granting
        // live.view the three section capabilities — which would drag Orders,
        // Bill requests and Tables back into the sidebar and defeat the point —
        // each read surface accepts either its own view or live.view.
        //
        // Derived, so they never appear as checkboxes: the role editor offers
        // "Live board" once, not three near-duplicates.
        $orLive = fn (TenantCapability $own) => fn (User $user) => $user->holdsTenantCapability($own)
            || $user->holdsTenantCapability(TenantCapability::LIVE_VIEW);

        Gate::define('orders.read', $orLive(TenantCapability::ORDERS_VIEW));
        Gate::define('bills.read', $orLive(TenantCapability::BILLS_VIEW));
        Gate::define('tables.live', $orLive(TenantCapability::TABLES_VIEW));
    }

    /**
     * Named rate limiters. `login` layers a per-account limit on top of the
     * per-IP one: a plain per-IP throttle does nothing to slow a distributed
     * brute force against a single known account, so also cap attempts per
     * (username, IP). Keying on username+IP — not username alone — avoids an
     * attacker being able to lock a victim out by hammering their username.
     */
    private function registerRateLimiters(): void
    {
        RateLimiter::for('login', function (Request $request) {
            $username = Str::lower(trim((string) $request->input('username')));

            return [
                Limit::perMinute(10)->by('login-ip:'.$request->ip()),
                Limit::perMinute(5)->by('login-acct:'.$username.'|'.$request->ip()),
            ];
        });

        // POS licence activation is unauthenticated — the key is the credential
        // — so it gets the same two-axis treatment as login: a per-IP cap, plus
        // a per-key cap so a distributed guess against one known key is slowed
        // even when the source addresses vary. Keyed on the hash, never the key
        // itself, so a rate-limit cache entry is not a credential store.
        // Pairing-code claim (POS-BE-023) is unauthenticated — the code is
        // the credential — so it gets the login treatment: per-IP plus
        // per-slug, so hammering one tenant's slug is slowed even from many
        // addresses. The code itself is never a limiter key (8 chars of
        // keyspace would make the cache a partial credential store).
        RateLimiter::for('pos-claim', function (Request $request) {
            $slug = Str::lower(trim((string) $request->input('tenant_slug')));

            return [
                Limit::perMinute(10)->by('pos-claim-ip:'.$request->ip()),
                Limit::perMinute(5)->by('pos-claim-slug:'.$slug.'|'.$request->ip()),
            ];
        });

        RateLimiter::for('licence-activate', function (Request $request) {
            $key = LicenceKey::hash((string) $request->input('key'));

            return [
                Limit::perMinute(10)->by('licence-ip:'.$request->ip()),
                Limit::perMinute(5)->by('licence-key:'.$key),
            ];
        });
    }

    /**
     * Stateless JWT guard: resolve the authenticated user from the request's
     * Bearer token. Backs the `jwt` guard referenced by `auth:jwt` routes.
     */
    private function registerJwtGuard(): void
    {
        Auth::viaRequest('jwt', function (Request $request): ?User {
            $token = $request->bearerToken();

            if (! $token) {
                return null;
            }

            $claims = Jwt::parse($token);

            if (! $claims || empty($claims['sub'])) {
                return null;
            }

            $user = User::find($claims['sub']);

            // Reject tokens for accounts that are gone or no longer active, and
            // tokens whose tenant claim no longer matches the account (defends
            // against a stale token after a tenant reassignment).
            if (! $user || $user->status !== UserStatus::ACTIVE) {
                return null;
            }

            if (($claims['rid'] ?? null) !== $user->restaurant_id) {
                return null;
            }

            // Reject any token minted before the password last changed. A
            // password reset/change stamps password_changed_at, so a stolen
            // token cannot outlive the victim's recovery (tokens carry `iat`).
            if ($user->password_changed_at !== null
                && (int) ($claims['iat'] ?? 0) < $user->password_changed_at->getTimestamp()) {
                return null;
            }

            return $user;
        });
    }
}

<?php

namespace App\Providers;

use App\Enums\Capability;
use App\Enums\RoleEnum;
use App\Enums\UserStatus;
use App\Models\User;
use App\Support\Jwt;
use Illuminate\Auth\Notifications\ResetPassword;
use Illuminate\Cache\RateLimiting\Limit;
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
        $this->registerJwtGuard();
        $this->registerRateLimiters();
        $this->registerGates();
        $this->registerPasswordResetUrl();
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

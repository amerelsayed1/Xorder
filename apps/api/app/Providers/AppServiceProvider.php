<?php

namespace App\Providers;

use App\Enums\UserStatus;
use App\Models\User;
use App\Support\Jwt;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\ServiceProvider;

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

            return $user;
        });
    }
}

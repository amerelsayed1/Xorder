<?php

namespace App\Http\Controllers\Auth;

use App\Enums\UserStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Auth\LoginRequest;
use App\Http\Resources\UserResource;
use App\Models\Restaurant;
use App\Services\AuditLogger;
use App\Support\Jwt;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;

class AuthController extends Controller
{
    /**
     * JWT login: verify the credentials against the tenant the request targets,
     * then mint a stateless access token. The token is the client's sole
     * credential for subsequent `auth:jwt` requests.
     */
    public function login(LoginRequest $request): JsonResponse
    {
        // Usernames are unique per tenant, so the account is only unambiguous
        // once we know the tenant. It comes from the `restaurant` slug the SPA
        // sends (falling back to the Host subdomain): {slug} is that restaurant;
        // the super-admin portal sends no slug and resolves to null. This also
        // means an account can only sign in on its own tenant.
        $tenantId = $this->resolveLoginTenantId($request);
        $credentials = [
            'username' => $request->input('username'),
            'restaurant_id' => $tenantId,
            'password' => $request->input('password'),
        ];

        // Reuse the Eloquent provider so tenant-scoped lookup and password
        // hashing behave exactly as the framework's own auth would.
        $provider = Auth::createUserProvider('users');
        $user = $provider->retrieveByCredentials($credentials);

        // Wrong username/password is an authentication failure → 401 (not a
        // 422 validation error: the request itself is well-formed).
        if (! $user || ! $provider->validateCredentials($user, $credentials)) {
            AuditLogger::record('auth.login_failed', [
                'restaurant_id' => $tenantId,
                'actor_role' => 'ANONYMOUS',
                'description' => sprintf('Failed login for "%s"', $request->input('username')),
            ]);

            return response()->json(['message' => __('auth.failed')], 401);
        }

        // A known account that isn't allowed in (suspended/inactive) → 403.
        if ($user->status !== UserStatus::ACTIVE) {
            AuditLogger::record('auth.login_blocked', [
                'actor' => $user,
                'auditable' => $user,
                'description' => sprintf('Blocked login — account is %s', $user->status->value),
            ]);

            return response()->json(['message' => __('xorder.errors.account_suspended')], 403);
        }

        $user->loadMissing('restaurant.features');
        $token = Jwt::issue($user);

        AuditLogger::record('auth.login', [
            'actor' => $user,
            'auditable' => $user,
            'description' => 'Signed in',
        ]);

        return response()->json([
            'data' => UserResource::make($user),
            'token' => $token,
            'token_type' => 'Bearer',
            'expires_in' => (int) config('jwt.ttl') * 60,
            'message' => __('xorder.messages.logged_in'),
        ]);
    }

    /**
     * The restaurant a login request targets.
     *
     * Prefer an explicit `restaurant` slug from the client: the SPA already
     * knows which subdomain it is serving, and sending it makes tenant login
     * work even when the Host header can't be trusted — a dev proxy that
     * rewrites it (`changeOrigin`) or a decoupled API origin (the SPA on
     * {slug}.<domain> calling api.<domain>). The Host subdomain remains the
     * fallback for same-origin requests that omit the hint.
     *
     * {slug} → that restaurant's id; the super-admin host (admin.<domain>, a
     * reserved/unknown subdomain, or a bare host) → null.
     */
    private function resolveLoginTenantId(Request $request): ?int
    {
        $slug = $request->input('restaurant');
        if (is_string($slug) && $slug !== '') {
            return Restaurant::where('slug', strtolower($slug))->value('id');
        }

        $host = strtolower($request->getHost());
        $sub = strtok($host, '.');

        // Bare host (no subdomain) → super-admin portal.
        if ($sub === $host) {
            return null;
        }

        // Reserved / unknown subdomains match no restaurant → null (super host).
        return Restaurant::where('slug', $sub)->value('id');
    }

    public function logout(Request $request): JsonResponse
    {
        AuditLogger::record('auth.logout', [
            'actor' => $request->user(),
            'auditable' => $request->user(),
            'description' => 'Signed out',
        ]);

        // Stateless JWT: there is no server-side session to tear down — the
        // client discards its token. The token's TTL bounds a leaked token's
        // remaining lifetime; add a token blocklist here if hard revocation is
        // ever required.
        return response()->json(['message' => __('xorder.messages.logged_out')]);
    }

    /** Current authenticated user + restaurant context (for the SPA bootstrap). */
    public function me(Request $request): JsonResponse
    {
        $user = $request->user()->loadMissing('restaurant.features');

        return response()->json(['data' => UserResource::make($user)]);
    }
}

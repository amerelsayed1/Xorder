<?php

namespace App\Http\Middleware;

use App\Enums\UserStatus;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Coarse role gate. Usage: ->middleware('role:SUPER_ADMIN').
 * Also rejects suspended user accounts outright.
 */
class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if ($user === null) {
            abort(401, __('xorder.errors.unauthenticated'));
        }

        if ($user->status !== UserStatus::ACTIVE) {
            abort(403, __('xorder.errors.account_suspended'));
        }

        if (! in_array($user->role->value, $roles, true)) {
            abort(403, __('xorder.errors.no_access'));
        }

        return $next($request);
    }
}

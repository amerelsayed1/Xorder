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
            abort(401, 'Unauthenticated.');
        }

        if ($user->status !== UserStatus::ACTIVE) {
            abort(403, 'Your account is suspended.');
        }

        if (! in_array($user->role->value, $roles, true)) {
            abort(403, 'You do not have access to this resource.');
        }

        return $next($request);
    }
}

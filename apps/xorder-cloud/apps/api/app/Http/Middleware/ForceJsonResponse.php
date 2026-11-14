<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * The API only ever speaks JSON. Force the Accept header so framework responses
 * (401 on auth, 422 on validation, 404, …) are always JSON — instead of, e.g.,
 * redirecting an unauthenticated request to the nonexistent `login` route
 * (which 500s) when a client forgets the Accept: application/json header.
 */
class ForceJsonResponse
{
    public function handle(Request $request, Closure $next): Response
    {
        $request->headers->set('Accept', 'application/json');

        return $next($request);
    }
}

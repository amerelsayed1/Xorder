<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Baseline hardening headers on every API response, and drop the runtime
 * version banner (X-Powered-By) so we don't advertise the PHP build. The API
 * returns JSON (not rendered HTML), so these are defense-in-depth: nosniff and
 * DENY-framing still matter for the rare error/redirect that a browser renders.
 *
 * Transport hardening (HSTS) belongs at the TLS-terminating ingress nginx, not
 * here — the app is reached over http:// behind the proxy. The canonical place
 * to suppress X-Powered-By is `expose_php = Off` in php.ini; this is a belt to
 * that suspenders so a misconfigured runtime still doesn't leak the version.
 */
class SecurityHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $response->headers->set('X-Content-Type-Options', 'nosniff');
        $response->headers->set('X-Frame-Options', 'DENY');
        $response->headers->set('Referrer-Policy', 'no-referrer');

        $response->headers->remove('X-Powered-By');
        if (! headers_sent()) {
            header_remove('X-Powered-By');
        }

        return $response;
    }
}

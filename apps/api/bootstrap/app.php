<?php

use App\Http\Middleware\EnsureFeatureEnabled;
use App\Http\Middleware\EnsureRole;
use App\Http\Middleware\EnsureSubscriptionAllowsWrites;
use App\Http\Middleware\ForceJsonResponse;
use App\Http\Middleware\PosDeviceAuth;
use App\Http\Middleware\SecurityHeaders;
use App\Http\Middleware\SetLocale;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\IpUtils;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Behind a reverse proxy (in production, the edge nginx -> the app's own
        // internal nginx) the app must trust forwarded headers, otherwise it
        // generates http:// URLs and drops the secure session cookie.
        //
        // Trust the private ranges the proxy chain actually runs on, NOT '*'.
        // Every hop between the client and PHP is on a private address, while a
        // real client is public — so Symfony walks X-Forwarded-For right to
        // left, discards the private hops, and stops at the first public entry:
        // the genuine client.
        //
        // '*' was wrong and actively exploitable. Trusting every hop makes
        // Symfony return the *leftmost* entry, and the leftmost entry is
        // whatever the caller put in the header — nginx appends to it rather
        // than replacing it. Any diner could send
        //   X-Forwarded-For: <the branch's Wi-Fi address>
        // and be recorded as sitting in the restaurant. Binding the container to
        // 127.0.0.1 does not help: the header still arrives through the proxy.
        // request()->ip() also keys the login rate limiter, so a forged value
        // let an attacker sidestep that too.
        $middleware->trustProxies(at: IpUtils::PRIVATE_SUBNETS);

        // API auth is stateless JWT (Authorization: Bearer) — no SPA session
        // cookie, so statefulApi()/CSRF is intentionally not enabled.
        $middleware->append(SetLocale::class);

        // API is JSON-only → framework errors (401/422/404) always render JSON.
        $middleware->prependToGroup('api', ForceJsonResponse::class);

        // Baseline hardening headers + drop the X-Powered-By version banner.
        $middleware->appendToGroup('api', SecurityHeaders::class);

        $middleware->alias([
            'role' => EnsureRole::class,
            'subscription.writable' => EnsureSubscriptionAllowsWrites::class,
            'feature' => EnsureFeatureEnabled::class,
            // The POS device credential (POS-BE-011 Option C). Not an auth
            // guard — see the middleware's own comment for why.
            'pos.device' => PosDeviceAuth::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*'),
        );

        // POS-BE-019: every 4xx from /api/pos/* carries {code, message,
        // details?}. Validation failures map to VALIDATION_FAILED with the
        // Laravel error bag in details — the client switches on `code`, never
        // on the HTTP status alone.
        $exceptions->render(function (ValidationException $e, Request $request) {
            if (! $request->is('api/pos/*')) {
                return null;
            }

            return response()->json([
                'code' => 'VALIDATION_FAILED',
                'message' => $e->getMessage(),
                'details' => ['errors' => $e->errors()],
            ], 422);
        });
    })->create();

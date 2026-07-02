<?php

use App\Http\Middleware\EnsureRole;
use App\Http\Middleware\EnsureSubscriptionAllowsWrites;
use App\Http\Middleware\ForceJsonResponse;
use App\Http\Middleware\SetLocale;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Behind a reverse proxy (in production, Operix's nginx -> the app's own
        // internal nginx) the app must trust forwarded headers, otherwise it
        // generates http:// URLs and drops the secure session cookie. Ingress is
        // only ever through the trusted proxy chain, so trust all hops.
        $middleware->trustProxies(at: '*');

        // Enable Sanctum SPA cookie authentication for first-party requests.
        $middleware->statefulApi();
        $middleware->append(SetLocale::class);

        // API is JSON-only → framework errors (401/422/404) always render JSON.
        $middleware->prependToGroup('api', ForceJsonResponse::class);

        $middleware->alias([
            'role' => EnsureRole::class,
            'subscription.writable' => EnsureSubscriptionAllowsWrites::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*'),
        );
    })->create();

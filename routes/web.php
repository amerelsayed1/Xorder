<?php

use App\Http\Controllers\Public\PublicMenuController;
use Illuminate\Support\Facades\Route;

$menuDomain = config('platform.menu_domain');

/*
|--------------------------------------------------------------------------
| Public menu — per-restaurant subdomain
|--------------------------------------------------------------------------
| When a menu domain is configured, each restaurant is served on its own
| subdomain: https://{slug}.tryorder.net/menu  (requires wildcard DNS + TLS).
| The root of the subdomain redirects to /menu.
*/
if ($menuDomain) {
    Route::domain('{slug}.'.$menuDomain)->group(function () {
        Route::get('/', fn (string $slug) => redirect('/menu'));
        Route::get('/menu', [PublicMenuController::class, 'show'])
            ->where('slug', '[a-z0-9-]+')
            ->name('public.menu');
    });
}

/*
|--------------------------------------------------------------------------
| Public menu — path fallback (always available; primary for local/dev)
|--------------------------------------------------------------------------
*/
Route::get('/r/{slug}', [PublicMenuController::class, 'show'])
    ->where('slug', '[a-z0-9-]+')
    ->name($menuDomain ? 'public.menu.path' : 'public.menu');

/*
|--------------------------------------------------------------------------
| SPA shell — Super Admin portal + Restaurant dashboard
|--------------------------------------------------------------------------
| Everything that is not an API call or a public menu URL is handed to the
| Vue SPA, which owns client-side routing (/login, /admin/*, /dashboard/*).
*/
Route::view('/{any?}', 'app')
    ->where('any', '^(?!api|r/|menu|build|storage).*$')
    ->name('spa');

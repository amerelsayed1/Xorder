<?php

use App\Http\Controllers\Public\MenuShellController;
use App\Http\Controllers\Public\SitemapController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public menu — Vue SPA shell served through Laravel
|--------------------------------------------------------------------------
| The guest menu is the Vue SPA in apps/menu, but its HTML entry is served
| by Laravel (nginx falls back to PHP for non-asset /menu/ URIs) so each
| restaurant's <head> carries real SEO/OG/JSON-LD tags — WhatsApp and other
| link-preview bots never execute JavaScript. Menu data stays on /api/*.
*/

Route::get('/menu/{path?}', [MenuShellController::class, 'show'])
    ->where('path', '.*');

// Legacy path-based menu URLs (early printed QR codes point here).
Route::get('/r/{slug}', [MenuShellController::class, 'legacy']);

// Landing + all visible restaurant menus, for crawlers.
Route::get('/sitemap.xml', [SitemapController::class, 'index']);

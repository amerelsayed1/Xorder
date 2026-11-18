<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Services\MenuShellService;
use App\Services\PublicMenuService;
use Illuminate\Http\RedirectResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class MenuShellController extends Controller
{
    public function __construct(
        private readonly PublicMenuService $menu,
        private readonly MenuShellService $shell,
    ) {}

    /**
     * {slug}.domain/menu — the guest-menu SPA shell with per-restaurant SEO
     * meta injected server-side. nginx falls back here for any /menu/ URI
     * that is not a static asset.
     */
    public function show(Request $request): Response
    {
        // Same resolution the SPA uses client-side: first hostname label.
        $slug = strtolower(strtok($request->getHost(), '.'));
        $restaurant = $this->menu->findBySlug($slug);
        $visible = $restaurant !== null && $this->menu->isVisible($restaurant);

        $html = $this->shell->render($restaurant, $visible);
        abort_if($html === null, 503, 'Menu app is not built.');

        // Unknown slug → 404 so crawlers drop the URL; the body still carries
        // the SPA, which renders its own "unavailable" screen.
        $response = response($html, $restaurant === null ? 404 : 200)
            ->header('Content-Type', 'text/html; charset=utf-8')
            ->header('Cache-Control', 'no-cache');

        // Order-tracking links (/menu/o/{token}) belong to one diner, and the
        // join page (/menu/p) is the same code page for everyone: neither is
        // for a search index. Crawlers do not run the page's JavaScript, so say
        // it here.
        if ($request->is('menu/o/*', 'menu/p')) {
            $response->header('X-Robots-Tag', 'noindex, nofollow');
        }

        return $response;
    }

    /**
     * Legacy /r/{slug} links (early printed QR codes, README fallback).
     * With MENU_DOMAIN configured the canonical menu lives on the subdomain,
     * so redirect; without it (path-based dev) serve the shell directly.
     */
    public function legacy(Request $request, string $slug): Response|RedirectResponse
    {
        $restaurant = $this->menu->findBySlug($slug);
        abort_if($restaurant === null, 404);

        if (config('platform.menu_domain')) {
            return redirect()->away($restaurant->publicUrl(), 302);
        }

        $html = $this->shell->render($restaurant, $this->menu->isVisible($restaurant));
        abort_if($html === null, 503, 'Menu app is not built.');

        return response($html)
            ->header('Content-Type', 'text/html; charset=utf-8')
            ->header('Cache-Control', 'no-cache');
    }
}

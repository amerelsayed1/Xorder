<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\PublicMenuService;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Cache;

class SitemapController extends Controller
{
    /**
     * Landing page + every publicly visible restaurant menu. Cached for an
     * hour — crawler traffic must not hit the restaurants table per request.
     */
    public function index(PublicMenuService $menu): Response
    {
        $xml = Cache::remember('sitemap.xml', 3600, function () use ($menu) {
            $urls = collect([[
                'loc' => rtrim(config('app.url'), '/'),
                'changefreq' => 'weekly',
            ]]);

            Restaurant::query()
                ->orderBy('id')
                ->get()
                ->filter(fn (Restaurant $r) => $menu->isVisible($r))
                ->each(function (Restaurant $r) use (&$urls) {
                    $urls->push([
                        'loc' => $r->publicUrl(),
                        'lastmod' => $r->updated_at?->toDateString(),
                        'changefreq' => 'daily',
                    ]);
                });

            $entries = $urls->map(function (array $url) {
                $parts = collect($url)
                    ->filter()
                    ->map(fn ($value, $tag) => "<{$tag}>".e($value)."</{$tag}>")
                    ->implode('');

                return "  <url>{$parts}</url>";
            })->implode("\n");

            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
                ."<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n"
                .$entries."\n</urlset>\n";
        });

        return response($xml, 200)->header('Content-Type', 'application/xml; charset=utf-8');
    }
}

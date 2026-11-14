<?php

namespace App\Support;

/**
 * Serves our own uploaded images from whatever host the page is already on.
 *
 * Uploads get an absolute URL baked in at upload time — Laravel's public disk
 * stitches APP_URL onto the path — and APP_URL is the apex, https://xorder.io.
 * A diner is on {slug}.xorder.io, so the menu API was handing them a second
 * origin for the hero cover, the logo and every item photo. Chrome coalesces
 * the two connections (same IP, one *.xorder.io certificate, HTTP/2) but WebKit
 * does not, so on the iPhones most QR scans come from, the LCP image paid a
 * fresh DNS + TCP + TLS handshake before its first byte.
 *
 * Emitting the path alone lets the browser resolve it against the page's own
 * origin. That is correct on every host the app is served from — apex, tenant
 * subdomain, local Docker, `php artisan serve` — and, unlike rebuilding an
 * absolute URL from the request, it cannot get the scheme wrong when a proxy
 * header is missing.
 *
 * Only our own /storage mount is touched. An image imported from someone
 * else's CDN is returned exactly as stored.
 */
final class PublicImageUrl
{
    /** Rewrite one stored image URL to a root-relative path when it is ours. */
    public static function relative(?string $url): ?string
    {
        if ($url === null || $url === '') {
            return null;
        }

        $parts = parse_url($url);
        if ($parts === false) {
            return $url;
        }

        $host = $parts['host'] ?? null;
        if ($host !== null && ! self::isOurs($host)) {
            return $url;
        }

        $path = $parts['path'] ?? '';
        $marker = strpos($path, '/storage/');
        if ($marker === false) {
            return $url;
        }

        return substr($path, $marker);
    }

    /**
     * Is this host served by us? The apex from APP_URL, plus the menu domain
     * and any tenant subdomain under it.
     */
    private static function isOurs(string $host): bool
    {
        $host = strtolower($host);

        $appHost = parse_url((string) config('app.url'), PHP_URL_HOST);
        if (is_string($appHost) && $host === strtolower($appHost)) {
            return true;
        }

        $menuDomain = config('platform.menu_domain');
        if (is_string($menuDomain) && $menuDomain !== '') {
            $menuDomain = strtolower($menuDomain);
            if ($host === $menuDomain || str_ends_with($host, '.'.$menuDomain)) {
                return true;
            }
        }

        return false;
    }
}

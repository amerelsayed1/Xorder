<?php

namespace App\Services;

use Illuminate\Support\Facades\Http;

/**
 * Turns a pasted Google Maps location (a full URL, a mobile "share" short link,
 * or a raw "lat,lng" string) into a [latitude, longitude] pair.
 *
 * Restaurant owners rarely know how to read raw coordinates off Google Maps, so
 * the profile form lets them paste whatever the "Share" button gives them. Long
 * URLs already carry the coordinates in the query/path and are parsed with no
 * network call; short links (maps.app.goo.gl, goo.gl) carry nothing, so we
 * follow their redirects — one hop at a time, re-validating the host each hop —
 * until the expanded URL reveals the coordinates.
 */
class MapLinkResolver
{
    /**
     * Hosts we will issue an outbound request to. Kept to Google's own map/short
     * domains: this is the SSRF guard — an arbitrary user-supplied URL is never
     * fetched, and every redirect target is re-checked against this list before
     * the next hop.
     */
    private const ALLOWED_HOSTS = [
        'maps.app.goo.gl',
        'goo.gl',
        'g.co',
        'google.com',
        'www.google.com',
        'maps.google.com',
    ];

    private const MAX_REDIRECTS = 5;

    /**
     * @return array{latitude: float, longitude: float}|null
     */
    public function resolve(string $input): ?array
    {
        $input = trim($input);
        if ($input === '') {
            return null;
        }

        // Fast path: the string already contains coordinates (raw pair, or a
        // full maps URL). No network needed.
        if ($coords = $this->parse($input)) {
            return $coords;
        }

        // Slow path: a short share link carries no coordinates — follow the
        // redirect chain (host-checked each hop) until they appear.
        $url = $input;
        for ($hop = 0; $hop < self::MAX_REDIRECTS; $hop++) {
            if (! $this->isAllowedUrl($url)) {
                return null;
            }
            try {
                $response = Http::withoutRedirecting()->timeout(6)->get($url);
            } catch (\Throwable) {
                return null;
            }
            $location = $response->header('Location');
            if ($location === '' || $location === null) {
                // Not a redirect — coordinates may be embedded in the final page.
                return $this->parse((string) $response->body());
            }
            $url = $this->absolutize($location, $url);
            if ($coords = $this->parse($url)) {
                return $coords;
            }
        }

        return null;
    }

    /**
     * Extract the first plausible coordinate pair from a URL or free text.
     *
     * @return array{latitude: float, longitude: float}|null
     */
    public function parse(string $text): ?array
    {
        $text = urldecode($text);

        $patterns = [
            // Place pin embedded in the data param — the most accurate marker.
            '/!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)/',
            // Map viewport / pin: .../@lat,lng,17z
            '/@(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/',
            // Query-style destinations: ?q= / query= / ll= / destination= / center= / sll= / daddr=
            '/[?&](?:q|query|ll|destination|center|sll|daddr)=(-?\d+(?:\.\d+)?),\s*(-?\d+(?:\.\d+)?)/i',
            // A bare "lat,lng" pair (also matches "loc:lat,lng").
            '/(-?\d{1,2}(?:\.\d+)?),\s*(-?\d{1,3}(?:\.\d+)?)/',
        ];

        foreach ($patterns as $pattern) {
            if (preg_match($pattern, $text, $m)) {
                $lat = (float) $m[1];
                $lng = (float) $m[2];
                if ($this->inRange($lat, $lng)) {
                    return ['latitude' => $lat, 'longitude' => $lng];
                }
            }
        }

        return null;
    }

    private function inRange(float $lat, float $lng): bool
    {
        return $lat >= -90 && $lat <= 90 && $lng >= -180 && $lng <= 180
            // Reject 0,0 (null-island): almost always a mis-parse, never a real venue.
            && ! ($lat === 0.0 && $lng === 0.0);
    }

    private function isAllowedUrl(string $url): bool
    {
        $host = strtolower((string) parse_url($url, PHP_URL_HOST));

        return $host !== '' && in_array($host, self::ALLOWED_HOSTS, true);
    }

    /** Resolve a possibly-relative redirect target against the URL it came from. */
    private function absolutize(string $location, string $base): string
    {
        if (preg_match('#^https?://#i', $location)) {
            return $location;
        }
        $scheme = parse_url($base, PHP_URL_SCHEME) ?: 'https';
        $host = parse_url($base, PHP_URL_HOST);

        return $host ? "{$scheme}://{$host}".'/'.ltrim($location, '/') : $location;
    }
}

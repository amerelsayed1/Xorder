<?php

namespace App\Support;

use Illuminate\Http\Request;

/**
 * Decides whether a public menu request should count toward the restaurant's
 * view analytics. The raw endpoint fires on every menu-JSON GET, so without a
 * gate a brand-new menu tallies "views" from the owner previewing their own
 * setup and from link-preview / monitoring crawlers — traffic no real diner
 * generated. Only genuine diner views should reach the counter.
 */
class MenuViewGate
{
    /**
     * User-agent substrings for crawlers, link-preview fetchers, uptime
     * monitors and scripted HTTP clients. None of these are real diners.
     * Matched case-insensitively as a substring of the UA.
     */
    private const BOT_SIGNATURES = [
        // Generic crawler markers
        'bot', 'crawler', 'spider', 'crawling',
        // Link-preview / social unfurlers
        'facebookexternalhit', 'facebot', 'whatsapp', 'telegrambot',
        'slackbot', 'twitterbot', 'discordbot', 'linkedinbot',
        'pinterest', 'embedly', 'redditbot', 'skypeuripreview', 'vkshare',
        // Search engines
        'googlebot', 'bingbot', 'yandex', 'duckduckbot', 'baiduspider', 'applebot',
        // SEO / misc crawlers
        'petalbot', 'ahrefs', 'semrush', 'mj12bot', 'dotbot',
        // Uptime / monitoring
        'pingdom', 'uptimerobot', 'statuscake', 'headlesschrome', 'phantomjs',
        // Scripted HTTP clients (never a real diner's browser)
        'curl', 'wget', 'python-requests', 'python-httpx', 'go-http-client',
        'okhttp', 'java/', 'node-fetch', 'guzzlehttp', 'axios/', 'libwww-perl',
    ];

    /**
     * A public menu request is countable only when it is a genuine diner view:
     * not an owner-initiated preview, and not an automated crawler / monitor.
     */
    public static function shouldCount(Request $request): bool
    {
        // Owner previews open the live menu with ?preview=1 (the admin "view my
        // menu" links carry it), so the owner checking their own setup does not
        // register as customer traffic. The customer QR / share URL stays clean.
        if ($request->boolean('preview')) {
            return false;
        }

        return ! self::isBot((string) $request->userAgent());
    }

    /**
     * A real diner always arrives through a browser, which always sends a
     * user-agent. A missing UA is a bare script, so it is treated as a bot.
     */
    public static function isBot(string $userAgent): bool
    {
        $ua = strtolower(trim($userAgent));

        if ($ua === '') {
            return true;
        }

        foreach (self::BOT_SIGNATURES as $needle) {
            if (str_contains($ua, $needle)) {
                return true;
            }
        }

        return false;
    }
}

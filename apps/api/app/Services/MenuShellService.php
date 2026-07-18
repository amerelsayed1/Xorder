<?php

namespace App\Services;

use App\Models\Restaurant;

/**
 * Serves the built guest-menu SPA (apps/menu) with per-restaurant SEO tags
 * injected into <head>. Link-preview bots (WhatsApp, Facebook, iMessage) and
 * some crawlers do not execute JavaScript, so the restaurant's name, image
 * and schema.org data must be present in the server response — a QR-menu
 * link is shared almost exclusively through WhatsApp.
 */
class MenuShellService
{
    /**
     * Locate the built SPA shell. Checked in order:
     *  - MENU_SHELL_PATH (env override; also used by tests)
     *  - /var/www/menu/index.html (Docker app image)
     *  - apps/menu/dist/index.html (host-based monorepo dev)
     */
    public function shellPath(): ?string
    {
        $candidates = array_filter([
            config('platform.menu_shell_path'),
            '/var/www/menu/index.html',
            base_path('../menu/dist/index.html'),
        ]);

        foreach ($candidates as $path) {
            if (is_file($path)) {
                return $path;
            }
        }

        return null;
    }

    /**
     * Render the shell for a restaurant. Returns null when the SPA has not
     * been built. Hidden/unknown restaurants get a noindex shell — the SPA
     * still renders its own "unavailable" screen client-side.
     */
    public function render(?Restaurant $restaurant, bool $visible): ?string
    {
        $path = $this->shellPath();
        if ($path === null) {
            return null;
        }

        $html = file_get_contents($path);

        if ($restaurant === null || ! $visible) {
            return $this->injectHead($html, '<meta name="robots" content="noindex">');
        }

        return $this->injectHead(
            $this->applyTitleAndLang($html, $restaurant),
            $this->metaTags($restaurant),
        );
    }

    private function applyTitleAndLang(string $html, Restaurant $restaurant): string
    {
        $title = e($this->displayName($restaurant));
        $html = preg_replace('/<title>.*?<\/title>/s', "<title>{$title}</title>", $html, 1);

        $lang = $restaurant->default_language->value;
        $dir = $lang === 'ar' ? 'rtl' : 'ltr';

        return preg_replace('/<html[^>]*>/', "<html lang=\"{$lang}\" dir=\"{$dir}\">", $html, 1);
    }

    private function metaTags(Restaurant $restaurant): string
    {
        $url = $restaurant->publicUrl();
        $name = $this->displayName($restaurant);
        $description = $this->displayDescription($restaurant);
        $image = $this->absoluteImage($restaurant);
        $logo = $this->toAbsolute($restaurant->logo_url, $restaurant);

        $tags = array_filter([
            $description ? '<meta name="description" content="'.e($description).'">' : null,
            // Per-restaurant favicon: the guest-menu shell ships with no icon,
            // so each restaurant's tab shows its own logo when one is set.
            $logo ? '<link rel="icon" href="'.e($logo).'">' : null,
            $logo ? '<link rel="apple-touch-icon" href="'.e($logo).'">' : null,
            '<link rel="canonical" href="'.e($url).'">',
            '<meta property="og:type" content="restaurant.menu">',
            '<meta property="og:site_name" content="'.e(config('app.name')).'">',
            '<meta property="og:title" content="'.e($name).'">',
            $description ? '<meta property="og:description" content="'.e($description).'">' : null,
            '<meta property="og:url" content="'.e($url).'">',
            $image ? '<meta property="og:image" content="'.e($image).'">' : null,
            '<meta name="twitter:card" content="'.($image ? 'summary_large_image' : 'summary').'">',
            '<script type="application/ld+json">'.$this->jsonLd($restaurant, $url, $image).'</script>',
        ]);

        return implode("\n    ", $tags);
    }

    private function jsonLd(Restaurant $restaurant, string $url, ?string $image): string
    {
        $data = array_filter([
            '@context' => 'https://schema.org',
            '@type' => 'Restaurant',
            'name' => $this->displayName($restaurant),
            'alternateName' => $restaurant->default_language->value === 'ar'
                ? $restaurant->name_en
                : $restaurant->name_ar,
            'description' => $this->displayDescription($restaurant),
            'url' => $url,
            'image' => $image,
            'telephone' => $restaurant->phone,
            'address' => $restaurant->address,
        ]);

        // Default slash-escaping keeps "</script>" from breaking out of the tag.
        return json_encode($data, JSON_UNESCAPED_UNICODE);
    }

    private function displayName(Restaurant $restaurant): string
    {
        return $restaurant->default_language->value === 'ar'
            ? ($restaurant->name_ar ?: $restaurant->name_en)
            : ($restaurant->name_en ?: $restaurant->name_ar);
    }

    private function displayDescription(Restaurant $restaurant): ?string
    {
        return $restaurant->default_language->value === 'ar'
            ? ($restaurant->description_ar ?: $restaurant->description_en)
            : ($restaurant->description_en ?: $restaurant->description_ar);
    }

    /** OG images must be absolute; uploads are stored as /storage/... paths. */
    private function absoluteImage(Restaurant $restaurant): ?string
    {
        return $this->toAbsolute($restaurant->cover_image_url ?: $restaurant->logo_url, $restaurant);
    }

    /** Resolve a stored /storage/... path (or existing absolute URL) to an absolute URL. */
    private function toAbsolute(?string $image, Restaurant $restaurant): ?string
    {
        if (! $image) {
            return null;
        }
        if (str_starts_with($image, 'http://') || str_starts_with($image, 'https://')) {
            return $image;
        }

        $parts = parse_url($restaurant->publicUrl());
        $origin = ($parts['scheme'] ?? 'https').'://'.($parts['host'] ?? '')
            .(isset($parts['port']) ? ':'.$parts['port'] : '');

        return $origin.'/'.ltrim($image, '/');
    }

    private function injectHead(string $html, string $block): string
    {
        return str_replace('</head>', "    {$block}\n</head>", $html);
    }
}

<?php

namespace App\Services;

use App\Models\Restaurant;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use Intervention\Image\ImageManager;

/**
 * Produces link-preview- and browser-friendly derivatives of a restaurant's
 * uploaded brand images. All uploads are stored as WebP (see ImageUploadService),
 * but WebP is not rendered by the WhatsApp / iMessage / Facebook link-preview
 * crawlers, nor by iOS Safari favicons. A QR menu is shared almost entirely
 * through WhatsApp, so the OG image MUST be a JPEG and the favicon a PNG.
 *
 * Derivatives are generated lazily on first use and cached on the public disk,
 * keyed off the source filename — so a new upload (new ULID) yields a fresh
 * derivative automatically and there is nothing to backfill for existing menus.
 * Every failure path returns null; callers fall back to the original URL so a
 * conversion problem never breaks the menu page.
 */
class BrandImageService
{
    private const CACHE_DIR = 'brand-cache';

    public function __construct(private ImageManager $imageManager) {}

    /**
     * WhatsApp/Facebook-compatible OG image (JPEG). Prefers the cover, falling
     * back to the logo. Returns [url, width, height] or null when unavailable.
     *
     * @return array{url: string, width: int, height: int}|null
     */
    public function ogImage(Restaurant $restaurant): ?array
    {
        return $this->derive(
            $restaurant->cover_image_url ?: $restaurant->logo_url,
            'og',
            'jpg',
        );
    }

    /**
     * Safari/iOS-compatible favicon + apple-touch-icon (PNG, alpha preserved).
     * Returns the derivative URL or null when the restaurant has no logo.
     */
    public function icon(Restaurant $restaurant): ?string
    {
        $result = $this->derive($restaurant->logo_url, 'icon', 'png');

        return $result['url'] ?? null;
    }

    /**
     * Resolve a stored image URL to a cached derivative in the given format.
     * Returns null for external/unrecognised URLs or on any conversion error.
     *
     * @return array{url: string, width: int, height: int}|null
     */
    private function derive(?string $sourceUrl, string $variant, string $extension): ?array
    {
        $sourcePath = $this->diskPath($sourceUrl);
        if ($sourcePath === null) {
            return null;
        }

        $disk = Storage::disk(config('platform.uploads.disk', 'public'));

        $target = self::CACHE_DIR.'/'.pathinfo($sourcePath, PATHINFO_FILENAME)."-{$variant}.{$extension}";

        try {
            if (! $disk->exists($sourcePath)) {
                return null;
            }

            if (! $disk->exists($target)) {
                $image = $this->imageManager->decodeBinary($disk->get($sourcePath));
                // Icons are square-cropped to a favicon-friendly size; the OG
                // image keeps its aspect ratio (WhatsApp shows a wide card).
                if ($variant === 'icon') {
                    $image->cover(256, 256);
                } else {
                    $image->scaleDown(width: 1200, height: 1200);
                }

                if (! $disk->put($target, (string) $image->encodeUsingFileExtension($extension, quality: 85))) {
                    return null;
                }
            }

            $dimensions = @getimagesizefromstring($disk->get($target));

            return [
                'url' => $disk->url($target),
                'width' => (int) ($dimensions[0] ?? 0),
                'height' => (int) ($dimensions[1] ?? 0),
            ];
        } catch (\Throwable $e) {
            Log::warning('Brand image derivative failed', [
                'source' => $sourcePath,
                'variant' => $variant,
                'error' => $e->getMessage(),
            ]);

            return null;
        }
    }

    /**
     * Map a stored public URL (absolute or /storage-relative) to its path on
     * the uploads disk, e.g. "https://xorder.io/storage/logos/x.webp" -> "logos/x.webp".
     * Returns null for anything not served from our /storage mount.
     */
    private function diskPath(?string $url): ?string
    {
        if (! $url) {
            return null;
        }

        $path = parse_url($url, PHP_URL_PATH) ?: $url;
        $marker = '/storage/';
        $pos = strpos($path, $marker);
        if ($pos === false) {
            return null;
        }

        return ltrim(substr($path, $pos + strlen($marker)), '/');
    }
}

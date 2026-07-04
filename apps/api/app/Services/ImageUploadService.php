<?php

namespace App\Services;

use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;
use Intervention\Image\ImageManagerStatic as Image;

class ImageUploadService
{
    /**
     * Validate-and-store an uploaded image. The file is re-encoded (stripping
     * EXIF/metadata and any embedded payloads), constrained to a max dimension,
     * stored under a randomized name, and returned as a public URL.
     */
    public function store(UploadedFile $file, string $folder = 'uploads'): string
    {
        $disk = config('platform.uploads.disk', 'public');
        $maxDim = (int) config('platform.uploads.max_dimension', 2000);

        $image = Image::read($file->getRealPath());

        // Downscale only if larger than the cap; never upscale.
        $image->scaleDown(width: $maxDim, height: $maxDim);

        $encoded = $image->toWebp(quality: 85);

        $path = $folder . '/' . Str::ulid() . '.webp';
        Storage::disk($disk)->put($path, (string) $encoded);

        return Storage::disk($disk)->url($path);
    }
}

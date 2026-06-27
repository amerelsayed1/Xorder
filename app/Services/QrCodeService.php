<?php

namespace App\Services;

use App\Models\Restaurant;
use SimpleSoftwareIO\QrCode\Facades\QrCode;

class QrCodeService
{
    /** Inline SVG string for on-screen preview (no image extension needed). */
    public function svg(Restaurant $restaurant, int $size = 320): string
    {
        return (string) QrCode::format('svg')
            ->size($size)
            ->margin(1)
            ->errorCorrection('M')
            ->generate($restaurant->publicUrl());
    }

    /** Binary PNG for download. */
    public function png(Restaurant $restaurant, int $size = 600): string
    {
        return (string) QrCode::format('png')
            ->size($size)
            ->margin(2)
            ->errorCorrection('M')
            ->generate($restaurant->publicUrl());
    }

    public function downloadFilename(Restaurant $restaurant): string
    {
        return "qr-{$restaurant->slug}.png";
    }
}

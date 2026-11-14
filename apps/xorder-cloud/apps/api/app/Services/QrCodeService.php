<?php

namespace App\Services;

use App\Models\DiningTable;
use App\Models\Restaurant;
use Illuminate\Support\Str;
use SimpleSoftwareIO\QrCode\Facades\QrCode;

class QrCodeService
{
    /** Inline SVG string for on-screen preview (no image extension needed). */
    public function svgForUrl(string $url, int $size = 320): string
    {
        return (string) QrCode::format('svg')
            ->size($size)
            ->margin(1)
            ->errorCorrection('M')
            ->generate($url);
    }

    /** Binary PNG for download. */
    public function pngForUrl(string $url, int $size = 600): string
    {
        return (string) QrCode::format('png')
            ->size($size)
            ->margin(2)
            ->errorCorrection('M')
            ->generate($url);
    }

    public function svg(Restaurant $restaurant, int $size = 320): string
    {
        return $this->svgForUrl($restaurant->publicUrl(), $size);
    }

    public function png(Restaurant $restaurant, int $size = 600): string
    {
        return $this->pngForUrl($restaurant->publicUrl(), $size);
    }

    public function downloadFilename(Restaurant $restaurant): string
    {
        return "qr-{$restaurant->slug}.png";
    }

    public function tableDownloadFilename(DiningTable $table): string
    {
        return "qr-table-{$table->public_token}.png";
    }

    /**
     * File name for a single table's QR inside a multi-table ZIP. Includes the
     * (slugged) label so the printed sheets are identifiable, and the token to
     * keep entries unique when two tables share a label.
     */
    public function tableZipEntryName(DiningTable $table): string
    {
        $label = Str::slug($table->label) ?: 'table';

        return "qr-{$label}-{$table->public_token}.png";
    }
}

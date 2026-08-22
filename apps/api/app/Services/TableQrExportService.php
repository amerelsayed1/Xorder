<?php

namespace App\Services;

use App\Http\Resources\DiningTableResource;
use App\Models\DiningTable;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

/**
 * The data twin of the QR ZIP export: every column the dashboard holds for a
 * table, plus the URL its QR encodes and the same PNG inline as base64. Self
 * contained on purpose — an external label designer can lay the codes out from
 * this payload alone, without a callback per table for the image.
 *
 * Shared by the tenant dashboard (`tables/qr/download-bulk?format=json`) and the
 * Super Admin per-restaurant export so the two can never drift apart.
 */
class TableQrExportService
{
    public function __construct(private readonly QrCodeService $qr) {}

    /**
     * @param  Collection<int, DiningTable>  $tables  with `restaurant` and
     *                                                `diningArea` eager-loaded
     */
    public function payload(Collection $tables, Request $request): array
    {
        $data = $tables->map(fn (DiningTable $table) => $this->row($table, $request));

        return [
            'exported_at' => now()->toIso8601String(),
            'count' => $data->count(),
            'data' => $data->all(),
        ];
    }

    private function row(DiningTable $table, Request $request): array
    {
        $url = $table->publicUrl();

        return [
            ...DiningTableResource::make($table)->toArray($request),
            'url' => $url,
            'qr_filename' => $this->qr->tableZipEntryName($table),
            'qr_png_base64' => base64_encode($this->qr->pngForUrl($url)),
        ];
    }
}

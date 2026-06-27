<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\QrCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;

class RestaurantQrController extends Controller
{
    public function __construct(private readonly QrCodeService $qr)
    {
    }

    public function show(Restaurant $restaurant): JsonResponse
    {
        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'svg' => $this->qr->svg($restaurant),
            ],
        ]);
    }

    public function download(Restaurant $restaurant): Response
    {
        return response($this->qr->png($restaurant), 200, [
            'Content-Type' => 'image/png',
            'Content-Disposition' => 'attachment; filename="' . $this->qr->downloadFilename($restaurant) . '"',
        ]);
    }
}

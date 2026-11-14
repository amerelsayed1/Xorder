<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Services\QrCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class DashboardQrController extends Controller
{
    public function __construct(private readonly QrCodeService $qr) {}

    public function show(Request $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        return response()->json([
            'data' => [
                'public_url' => $restaurant->publicUrl(),
                'svg' => $this->qr->svg($restaurant),
            ],
        ]);
    }

    public function download(Request $request): Response
    {
        $restaurant = $request->user()->restaurant;

        return response($this->qr->png($restaurant), 200, [
            'Content-Type' => 'image/png',
            'Content-Disposition' => 'attachment; filename="'.$this->qr->downloadFilename($restaurant).'"',
        ]);
    }
}

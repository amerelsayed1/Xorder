<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Services\QrCodeService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

/**
 * Guest paging, shared QR (docs/features/guest-paging-shared-qr): the restaurant's
 * one standing "counter" QR. Printed once; every client scans it and types the
 * number on their slip. Always the signed-in user's own restaurant, never an id
 * from the request.
 */
class PagerQrController extends Controller
{
    public function __construct(private readonly QrCodeService $qr) {}

    public function show(Request $request): JsonResponse
    {
        $url = $request->user()->restaurant->pagerJoinUrl();

        return response()->json([
            'data' => ['join_url' => $url, 'svg' => $this->qr->svgForUrl($url)],
        ]);
    }

    public function download(Request $request): Response
    {
        $restaurant = $request->user()->restaurant;

        return response($this->qr->pngForUrl($restaurant->pagerJoinUrl()), 200, [
            'Content-Type' => 'image/png',
            'Content-Disposition' => 'attachment; filename="qr-counter-'.$restaurant->slug.'.png"',
        ]);
    }
}

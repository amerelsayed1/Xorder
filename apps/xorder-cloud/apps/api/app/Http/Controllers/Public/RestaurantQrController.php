<?php

namespace App\Http\Controllers\Public;

use App\Http\Controllers\Controller;
use App\Models\Restaurant;
use App\Services\QrCodeService;
use Illuminate\Http\Response;

class RestaurantQrController extends Controller
{
    public function __construct(private readonly QrCodeService $qr) {}

    /**
     * Public SVG QR of a restaurant's menu URL. Used on the marketing site to
     * show a real, scannable code for the demo restaurant. Available for any
     * existing restaurant; returns 404 otherwise.
     */
    public function show(string $slug): Response
    {
        $restaurant = Restaurant::query()->where('slug', $slug)->first();

        if ($restaurant === null) {
            abort(404);
        }

        return response($this->qr->svg($restaurant), 200, [
            'Content-Type' => 'image/svg+xml',
            'Cache-Control' => 'public, max-age=86400',
        ]);
    }
}

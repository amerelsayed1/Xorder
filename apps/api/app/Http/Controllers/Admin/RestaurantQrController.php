<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\DiningTable;
use App\Models\Restaurant;
use App\Services\QrCodeService;
use App\Services\TableQrExportService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

class RestaurantQrController extends Controller
{
    public function __construct(private readonly QrCodeService $qr) {}

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
            'Content-Disposition' => 'attachment; filename="'.$this->qr->downloadFilename($restaurant).'"',
        ]);
    }

    /**
     * Every table of one restaurant as JSON — the same payload the tenant's own
     * `tables/qr/download-bulk?format=json` returns, but addressed by id so
     * support can pull a floor's codes without signing in as the restaurant.
     *
     * RestaurantScope is a deliberate no-op for Super Admins, so the
     * restaurant_id filter here is the only thing keeping this to one tenant —
     * it must stay explicit.
     */
    public function tablesExport(
        Request $request,
        Restaurant $restaurant,
        TableQrExportService $export,
    ): JsonResponse {
        $tables = DiningTable::query()
            ->where('restaurant_id', $restaurant->id)
            // publicUrl() reaches through to the restaurant for every table;
            // diningArea carries the area names the export lists.
            ->with(['restaurant', 'diningArea'])
            ->orderBy('dining_area_id')->orderBy('label')
            ->get();

        return response()->json([
            'restaurant' => [
                'id' => $restaurant->id,
                'slug' => $restaurant->slug,
                'name_en' => $restaurant->name_en,
                'name_ar' => $restaurant->name_ar,
            ],
            ...$export->payload($tables, $request),
        ]);
    }
}

<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Resources\PosTerminalResource;
use App\Models\PosTerminal;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * POS-BE-022's fleet views. DELIBERATELY CROSS-TENANT — the one POS surface
 * that must escape RestaurantScope (a Super Admin has no tenant context, so
 * the scope is a no-op; stated here so it is explicit rather than
 * incidental). Gated can:pos_fleet.view, SUPER_ADMIN-only by default.
 *
 * pending_count + oldest_pending_at are the headline columns: unsynced money
 * per till, in real time.
 */
class PosFleetController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $terminals = PosTerminal::query()
            ->with(['restaurant:id,name_en,name_ar,slug', 'branch:id,name_en,name_ar,code'])
            ->when($request->filled('restaurant_id'), fn ($q) => $q->where('restaurant_id', $request->integer('restaurant_id')))
            ->when($request->filled('state'), fn ($q) => $q->where('state', $request->string('state')))
            ->when($request->string('sort') === 'pending', fn ($q) => $q->orderByDesc('pending_count'), fn ($q) => $q->orderByDesc('last_seen_at'))
            ->paginate(50);

        return PosTerminalResource::collection($terminals)->response();
    }

    public function show(PosTerminal $terminal): JsonResponse
    {
        $terminal->load(['restaurant:id,name_en,name_ar,slug', 'branch:id,name_en,name_ar,code']);

        return response()->json(['data' => PosTerminalResource::make($terminal)]);
    }
}

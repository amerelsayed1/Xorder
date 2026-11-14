<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreUnitRequest;
use App\Http\Requests\Dashboard\UpdateUnitRequest;
use App\Models\Unit;
use App\Services\UnitCatalog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * CB-09 slice a: units. RestaurantScope isolates (a foreign id is a 404), and
 * the Auditable trait records every create and update.
 *
 * No destroy: a unit is retired with is_active = false. Nothing here is in the
 * POS bundle, so pos_config_version is deliberately not bumped.
 */
class UnitController extends Controller
{
    public function index(Request $request, UnitCatalog $catalog): JsonResponse
    {
        $catalog->ensureDefaults($request->user()->restaurant_id);

        return response()->json(['data' => Unit::orderBy('sort_order')->orderBy('id')->get()]);
    }

    public function show(Unit $unit): JsonResponse
    {
        return response()->json(['data' => $unit]);
    }

    public function store(StoreUnitRequest $request): JsonResponse
    {
        $unit = Unit::create($request->validated());

        return response()->json(['data' => $unit->fresh(), 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateUnitRequest $request, Unit $unit): JsonResponse
    {
        $unit->update($request->validated());

        return response()->json(['data' => $unit->fresh(), 'message' => __('xorder.messages.saved')]);
    }
}

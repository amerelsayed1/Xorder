<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreDiningAreaRequest;
use App\Http\Requests\Dashboard\UpdateDiningAreaRequest;
use App\Http\Resources\DiningAreaResource;
use App\Models\BillRequest;
use App\Models\DiningArea;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class DiningAreaController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $areas = DiningArea::withCount('tables')
            ->when($request->filled('branch_id'), fn ($q) => $q->where('branch_id', $request->integer('branch_id')))
            ->orderBy('display_order')->orderBy('id')
            ->get();

        return DiningAreaResource::collection($areas)->response();
    }

    public function store(StoreDiningAreaRequest $request): JsonResponse
    {
        // restaurant_id is stamped by the BelongsToRestaurant trait.
        $area = DiningArea::create($request->validated());

        return response()->json([
            'data' => DiningAreaResource::make($area),
            'message' => __('xorder.messages.area_created'),
        ], 201);
    }

    public function update(UpdateDiningAreaRequest $request, DiningArea $area): JsonResponse
    {
        $area->update($request->validated());

        return response()->json([
            'data' => DiningAreaResource::make($area->fresh()->loadCount('tables')),
            'message' => __('xorder.messages.area_updated'),
        ]);
    }

    /** PATCH is_active: set explicitly, or toggle when omitted. */
    public function toggleStatus(Request $request, DiningArea $area): JsonResponse
    {
        $request->validate(['is_active' => ['sometimes', 'boolean']]);

        $area->is_active = $request->has('is_active')
            ? $request->boolean('is_active')
            : ! $area->is_active;
        $area->save();

        return response()->json([
            'data' => DiningAreaResource::make($area->loadCount('tables')),
            'message' => __('xorder.messages.area_status_updated'),
        ]);
    }

    /**
     * Hard delete is only allowed with no historical activity (FR-AREA-007);
     * otherwise the area must be disabled to preserve history (BR-008).
     */
    public function destroy(DiningArea $area): JsonResponse
    {
        if ($area->orders()->exists()) {
            return response()->json(['message' => __('xorder.messages.area_has_history')], 409);
        }

        // Deleting the area cascades to its tables, which would orphan their open
        // bill requests; cancel them first (see BillRequest::cancelOpenForTables).
        DB::transaction(function () use ($area) {
            BillRequest::cancelOpenForTables($area->tables()->pluck('id')->all());
            $area->delete();
        });

        return response()->json(['message' => __('xorder.messages.area_deleted')]);
    }
}

<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreTenderTypeRequest;
use App\Http\Requests\Dashboard\UpdateTenderTypeRequest;
use App\Models\TenderType;
use Illuminate\Http\JsonResponse;

/**
 * POS-BE-013 authoring. DELETE deactivates rather than removing the row —
 * historical order_payments keep their tender FK, per the contract.
 */
class TenderTypeController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => TenderType::orderBy('sort_order')->orderBy('id')->get()]);
    }

    public function store(StoreTenderTypeRequest $request): JsonResponse
    {
        $tender = TenderType::create($request->validated());

        return response()->json(['data' => $tender, 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateTenderTypeRequest $request, TenderType $tenderType): JsonResponse
    {
        $tenderType->update($request->validated());

        return response()->json(['data' => $tenderType->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    public function destroy(TenderType $tenderType): JsonResponse
    {
        $tenderType->update(['is_active' => false]);

        return response()->json(['data' => $tenderType->fresh(), 'message' => __('xorder.messages.saved')]);
    }
}

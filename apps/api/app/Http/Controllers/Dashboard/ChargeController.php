<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreChargeRequest;
use App\Http\Requests\Dashboard\UpdateChargeRequest;
use App\Models\Charge;
use Illuminate\Http\JsonResponse;

/** POS-BE-013 authoring — see TaxRuleController. */
class ChargeController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => Charge::orderBy('sort_order')->orderBy('id')->get()]);
    }

    public function store(StoreChargeRequest $request): JsonResponse
    {
        $charge = Charge::create($request->validated());

        return response()->json(['data' => $charge, 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateChargeRequest $request, Charge $charge): JsonResponse
    {
        $charge->update($request->validated());

        return response()->json(['data' => $charge->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    public function destroy(Charge $charge): JsonResponse
    {
        $charge->delete();

        return response()->json(['message' => __('xorder.messages.deleted')]);
    }
}

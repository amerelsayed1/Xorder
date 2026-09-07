<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreTaxRuleRequest;
use App\Http\Requests\Dashboard\UpdateTaxRuleRequest;
use App\Models\TaxRule;
use Illuminate\Http\JsonResponse;

/**
 * POS-BE-013 authoring. RestaurantScope isolates; every write bumps
 * pos_config_version via the model hooks in PosConfigVersion.
 */
class TaxRuleController extends Controller
{
    public function index(): JsonResponse
    {
        return response()->json(['data' => TaxRule::orderBy('sort_order')->orderBy('id')->get()]);
    }

    public function store(StoreTaxRuleRequest $request): JsonResponse
    {
        $rule = TaxRule::create($request->validated());

        return response()->json(['data' => $rule, 'message' => __('xorder.messages.saved')], 201);
    }

    public function update(UpdateTaxRuleRequest $request, TaxRule $taxRule): JsonResponse
    {
        $taxRule->update($request->validated());

        return response()->json(['data' => $taxRule->fresh(), 'message' => __('xorder.messages.saved')]);
    }

    public function destroy(TaxRule $taxRule): JsonResponse
    {
        $taxRule->delete();

        return response()->json(['message' => __('xorder.messages.deleted')]);
    }
}

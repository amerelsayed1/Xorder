<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StorePlanRequest;
use App\Http\Requests\Admin\UpdatePlanRequest;
use App\Http\Resources\PlanResource;
use App\Models\Plan;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PlanController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $plans = Plan::query()
            ->when($request->boolean('active_only'), fn ($q) => $q->where('is_active', true))
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();

        return PlanResource::collection($plans)->response();
    }

    public function store(StorePlanRequest $request): JsonResponse
    {
        $plan = Plan::create($request->validated());

        return response()->json([
            'data' => PlanResource::make($plan),
            'message' => __('xorder.messages.plan_created'),
        ], 201);
    }

    public function show(Plan $plan): JsonResponse
    {
        return response()->json(['data' => PlanResource::make($plan)]);
    }

    public function update(UpdatePlanRequest $request, Plan $plan): JsonResponse
    {
        $plan->update($request->validated());

        return response()->json([
            'data' => PlanResource::make($plan->fresh()),
            'message' => __('xorder.messages.plan_updated'),
        ]);
    }

    public function destroy(Plan $plan): JsonResponse
    {
        $plan->delete();

        return response()->json(['message' => __('xorder.messages.plan_deleted')]);
    }
}

<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateSubscriptionRequest;
use App\Http\Resources\RestaurantResource;
use App\Models\Restaurant;
use App\Services\PlanEntitlementService;
use Illuminate\Http\JsonResponse;

class SubscriptionController extends Controller
{
    public function update(
        UpdateSubscriptionRequest $request,
        Restaurant $restaurant,
        PlanEntitlementService $entitlements,
    ): JsonResponse {
        $restaurant->update($request->validated());

        // The plan strictly decides features: changing the plan re-derives the
        // restaurant's capability flags.
        $entitlements->sync($restaurant->fresh());

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()->load('features')),
            'message' => __('xorder.messages.subscription_updated'),
        ]);
    }
}

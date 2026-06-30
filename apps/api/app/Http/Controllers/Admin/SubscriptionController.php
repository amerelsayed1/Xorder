<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateSubscriptionRequest;
use App\Http\Resources\RestaurantResource;
use App\Models\Restaurant;
use Illuminate\Http\JsonResponse;

class SubscriptionController extends Controller
{
    public function update(UpdateSubscriptionRequest $request, Restaurant $restaurant): JsonResponse
    {
        $restaurant->update($request->validated());

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => __('xorder.messages.subscription_updated'),
        ]);
    }
}

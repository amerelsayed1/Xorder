<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\UpdateRestaurantProfileRequest;
use App\Http\Resources\RestaurantResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RestaurantProfileController extends Controller
{
    public function show(Request $request): JsonResponse
    {
        return response()->json([
            'data' => RestaurantResource::make($request->user()->restaurant),
        ]);
    }

    public function update(UpdateRestaurantProfileRequest $request): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        $restaurant->update($request->validated());

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => __('xorder.messages.profile_updated'),
        ]);
    }
}

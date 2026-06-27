<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\UpdateRestaurantStatusRequest;
use App\Http\Resources\RestaurantResource;
use App\Models\Restaurant;
use Illuminate\Http\JsonResponse;

class RestaurantStatusController extends Controller
{
    public function update(UpdateRestaurantStatusRequest $request, Restaurant $restaurant): JsonResponse
    {
        $restaurant->update(['status' => $request->validated('status')]);

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => 'Restaurant status updated.',
        ]);
    }
}

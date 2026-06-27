<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StoreRestaurantRequest;
use App\Http\Requests\Admin\UpdateRestaurantRequest;
use App\Http\Resources\RestaurantResource;
use App\Models\Restaurant;
use App\Services\RestaurantProvisioningService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class RestaurantController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $restaurants = Restaurant::query()
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')))
            ->when($request->filled('search'), function ($q) use ($request) {
                $term = '%' . $request->string('search') . '%';
                $q->where(fn ($q) => $q
                    ->where('name_en', 'like', $term)
                    ->orWhere('name_ar', 'like', $term)
                    ->orWhere('slug', 'like', $term));
            })
            ->withCount(['categories', 'menuItems'])
            ->latest()
            ->paginate(20)
            ->withQueryString();

        return RestaurantResource::collection($restaurants)->response();
    }

    public function store(StoreRestaurantRequest $request, RestaurantProvisioningService $provisioner): JsonResponse
    {
        $result = $provisioner->provision(
            restaurantData: $request->safe()->except('admin'),
            adminData: $request->validated('admin'),
        );

        return response()->json([
            'data' => RestaurantResource::make($result['restaurant']),
            // Returned once so the Super Admin can hand the password over.
            'generated_password' => $result['generated_password'],
            'message' => 'Restaurant and admin created.',
        ], 201);
    }

    public function show(Restaurant $restaurant): JsonResponse
    {
        $restaurant->loadCount(['categories', 'menuItems'])->load('users');

        return response()->json(['data' => RestaurantResource::make($restaurant)]);
    }

    public function update(UpdateRestaurantRequest $request, Restaurant $restaurant): JsonResponse
    {
        $restaurant->update($request->validated());

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()),
            'message' => 'Restaurant updated.',
        ]);
    }
}

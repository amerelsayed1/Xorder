<?php

namespace App\Http\Controllers\Admin;

use App\Enums\RestaurantStatus;
use App\Http\Controllers\Controller;
use App\Http\Requests\Admin\StoreRestaurantRequest;
use App\Http\Requests\Admin\UpdateRestaurantRequest;
use App\Http\Resources\RestaurantResource;
use App\Models\Restaurant;
use App\Services\PlanEntitlementService;
use App\Services\RestaurantProvisioningService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class RestaurantController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $restaurants = Restaurant::query()
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->string('status')))
            ->when($request->filled('search'), function ($q) use ($request) {
                $term = '%'.$request->string('search').'%';
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
        $branch = $request->validated('branch');

        // No `features` argument: capabilities are derived strictly from the
        // chosen plan inside provisioning, so admin creation can't grant more
        // than the plan entitles.
        $result = $provisioner->provision(
            restaurantData: $request->safe()->except(['admin', 'branch', 'features']),
            adminData: $request->validated('admin'),
            branchData: filled($branch) ? $branch : null,
        );

        return response()->json([
            'data' => RestaurantResource::make($result['restaurant']),
            // Returned once so the Super Admin can hand the password over.
            'generated_password' => $result['generated_password'],
            'message' => __('xorder.messages.restaurant_admin_created'),
        ], 201);
    }

    public function show(Restaurant $restaurant): JsonResponse
    {
        $restaurant->loadCount(['categories', 'menuItems'])->load(['users', 'features']);

        return response()->json(['data' => RestaurantResource::make($restaurant)]);
    }

    public function update(UpdateRestaurantRequest $request, Restaurant $restaurant, PlanEntitlementService $entitlements): JsonResponse
    {
        $restaurant->update($request->safe()->except('features'));

        // Features are strictly derived from the plan — any hand-passed
        // `features` are ignored. Re-sync so a plan change here takes effect.
        $entitlements->sync($restaurant->fresh());

        return response()->json([
            'data' => RestaurantResource::make($restaurant->fresh()->load('features')),
            'message' => __('xorder.messages.restaurant_updated'),
        ]);
    }

    /**
     * Permanently delete a restaurant, its menu (categories + items cascade at
     * the DB level) and its admin users. This is irreversible.
     */
    public function destroy(Request $request, Restaurant $restaurant): JsonResponse
    {
        if ($restaurant->status !== RestaurantStatus::ARCHIVED) {
            return response()->json([
                'message' => __('xorder.messages.archive_before_delete'),
            ], 409);
        }

        $request->validate([
            'confirmation' => ['required', 'string', Rule::in([$restaurant->slug])],
        ], [
            'confirmation.in' => __('xorder.validation.delete_confirmation'),
        ]);

        DB::transaction(function () use ($restaurant) {
            // Remove the tenant's users explicitly; the FK would otherwise null
            // their restaurant_id and leave orphaned accounts behind.
            $restaurant->users()->delete();
            $restaurant->delete();
        });

        return response()->json(['message' => __('xorder.messages.restaurant_deleted')]);
    }
}

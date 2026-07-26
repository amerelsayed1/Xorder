<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ReorderRequest;
use App\Http\Requests\Dashboard\StoreCategoryRequest;
use App\Http\Requests\Dashboard\UpdateCategoryRequest;
use App\Http\Resources\CategoryResource;
use App\Models\Category;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class CategoryController extends Controller
{
    public function index(): JsonResponse
    {
        $categories = Category::withCount('menuItems')
            ->orderBy('display_order')
            ->orderBy('id')
            ->get();

        return CategoryResource::collection($categories)->response();
    }

    public function store(StoreCategoryRequest $request): JsonResponse
    {
        // restaurant_id is stamped by the BelongsToRestaurant trait.
        $category = Category::create($request->validated());

        return response()->json([
            'data' => CategoryResource::make($category),
            'message' => __('xorder.messages.category_created'),
        ], 201);
    }

    public function show(Category $category): JsonResponse
    {
        return response()->json([
            'data' => CategoryResource::make($category->loadCount('menuItems')),
        ]);
    }

    public function update(UpdateCategoryRequest $request, Category $category): JsonResponse
    {
        $category->update($request->validated());

        return response()->json([
            'data' => CategoryResource::make($category->fresh()),
            'message' => __('xorder.messages.category_updated'),
        ]);
    }

    /**
     * Soft-delete the category and cascade the soft-delete to its items so both
     * drop off the dashboard and the public menu together. Everything is
     * recoverable at the DB level via deleted_at (no restore UI yet, matching
     * how MenuItem uses SoftDeletes).
     */
    public function destroy(Category $category): JsonResponse
    {
        DB::transaction(function () use ($category) {
            $category->menuItems()->delete(); // soft-delete children (MenuItem uses SoftDeletes)
            $category->delete();              // soft-delete the category
        });

        return response()->json(['message' => __('xorder.messages.category_deleted')]);
    }

    /** PATCH status: set is_active explicitly, or toggle when omitted. */
    public function toggleStatus(Request $request, Category $category): JsonResponse
    {
        $request->validate(['is_active' => ['sometimes', 'boolean']]);

        $category->is_active = $request->has('is_active')
            ? $request->boolean('is_active')
            : ! $category->is_active;
        $category->save();

        return response()->json([
            'data' => CategoryResource::make($category),
            'message' => __('xorder.messages.category_status_updated'),
        ]);
    }

    public function reorder(ReorderRequest $request): JsonResponse
    {
        $order = collect($request->validated('order'));
        $ids = $order->pluck('id');

        // Only ids that belong to this tenant survive the scoped query.
        $ownedIds = Category::whereIn('id', $ids)->pluck('id');
        if ($ownedIds->count() !== $ids->unique()->count()) {
            return response()->json(['message' => __('xorder.messages.categories_not_found')], 422);
        }

        DB::transaction(function () use ($order) {
            foreach ($order as $row) {
                Category::whereKey($row['id'])->update(['display_order' => $row['display_order']]);
            }
        });

        return response()->json(['message' => __('xorder.messages.categories_reordered')]);
    }
}

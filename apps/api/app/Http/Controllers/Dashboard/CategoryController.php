<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\BulkDeleteCategoriesRequest;
use App\Http\Requests\Dashboard\BulkStoreCategoriesRequest;
use App\Http\Requests\Dashboard\ReorderRequest;
use App\Http\Requests\Dashboard\StoreCategoryRequest;
use App\Http\Requests\Dashboard\UpdateCategoryRequest;
use App\Http\Resources\CategoryResource;
use App\Models\Category;
use App\Models\Restaurant;
use App\Services\PlanLimitService;
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

    public function store(StoreCategoryRequest $request, PlanLimitService $limits): JsonResponse
    {
        $restaurant = $request->user()->restaurant;

        // Limit check + insert are serialized per tenant under a row lock so
        // concurrent creates cannot all slip past the plan's category cap.
        $result = DB::transaction(function () use ($restaurant, $limits, $request) {
            Restaurant::whereKey($restaurant->getKey())->lockForUpdate()->first();

            if (($limit = $limits->categoryLimitReached($restaurant)) !== null) {
                return ['limit' => $limit];
            }

            // restaurant_id is stamped by the BelongsToRestaurant trait.
            return ['category' => Category::create($request->validated())];
        });

        if (isset($result['limit'])) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_categories', ['limit' => $result['limit']]),
            ], 422);
        }

        return response()->json([
            'data' => CategoryResource::make($result['category']),
            'message' => __('xorder.messages.category_created'),
        ], 201);
    }

    /**
     * Create several categories in one request (XORD-007), all-or-nothing.
     *
     * Validation has already refused duplicates (against the menu and within
     * the batch) and rows with no name. What is left is the plan cap, counted
     * for the whole batch under the same tenant row lock `store()` takes, and
     * the insert itself, one transaction: an exception rolls every row back.
     * New rows are appended after the current last one, in the order sent.
     */
    public function bulkStore(BulkStoreCategoriesRequest $request, PlanLimitService $limits): JsonResponse
    {
        $restaurant = $request->user()->restaurant;
        // validated() lists a row where its first matching rule found it, not
        // where it was sent (a row with only name_ar comes before one with
        // name_en), so restore the order the owner typed them in.
        $rows = $request->validated('categories');
        ksort($rows);
        $rows = array_values($rows);

        $result = DB::transaction(function () use ($restaurant, $limits, $rows) {
            Restaurant::whereKey($restaurant->getKey())->lockForUpdate()->first();

            if (($limit = $limits->categoryLimitWouldBeExceeded($restaurant, count($rows))) !== null) {
                return ['limit' => $limit];
            }

            $next = ((int) Category::query()->max('display_order')) + 1;
            $created = [];
            foreach ($rows as $offset => $row) {
                // restaurant_id is stamped by the BelongsToRestaurant trait.
                $created[] = Category::create([
                    'name_ar' => $row['name_ar'] ?? null,
                    'name_en' => $row['name_en'] ?? null,
                    'is_active' => $row['is_active'] ?? true,
                    'display_order' => $next + $offset,
                ]);
            }

            return ['categories' => $created];
        });

        if (isset($result['limit'])) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_categories', ['limit' => $result['limit']]),
            ], 422);
        }

        return response()->json([
            'data' => CategoryResource::collection(collect($result['categories'])),
            'message' => trans_choice('xorder.messages.categories_created', count($result['categories']), ['count' => count($result['categories'])]),
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

    /**
     * Soft-delete several categories at once. Every id is verified against the
     * tenant scope first (same guard as reorder()), so a client cannot delete
     * categories outside its restaurant by injecting foreign ids. Each
     * category cascades the soft-delete to its items, matching destroy().
     */
    public function bulkDestroy(BulkDeleteCategoriesRequest $request): JsonResponse
    {
        $ids = collect($request->validated('ids'))->unique();

        $ownedIds = Category::whereIn('id', $ids)->pluck('id');
        if ($ownedIds->count() !== $ids->count()) {
            return response()->json(['message' => __('xorder.messages.categories_not_found')], 422);
        }

        DB::transaction(function () use ($ownedIds) {
            Category::whereIn('id', $ownedIds)->each(function (Category $category) {
                $category->menuItems()->delete(); // soft-delete children
                $category->delete();              // soft-delete the category
            });
        });

        return response()->json([
            'message' => trans_choice('xorder.messages.categories_deleted', $ownedIds->count(), ['count' => $ownedIds->count()]),
        ]);
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

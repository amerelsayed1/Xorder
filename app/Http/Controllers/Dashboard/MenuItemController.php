<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ReorderRequest;
use App\Http\Requests\Dashboard\StoreMenuItemRequest;
use App\Http\Requests\Dashboard\UpdateMenuItemRequest;
use App\Http\Resources\MenuItemResource;
use App\Models\MenuItem;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class MenuItemController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $items = MenuItem::query()
            ->when($request->filled('category_id'), fn ($q) => $q->where('category_id', $request->integer('category_id')))
            ->when($request->filled('availability'), function ($q) use ($request) {
                $q->where('is_available', $request->string('availability') === 'available');
            })
            ->when($request->filled('search'), function ($q) use ($request) {
                $term = '%' . $request->string('search') . '%';
                $q->where(fn ($q) => $q->where('name_en', 'like', $term)->orWhere('name_ar', 'like', $term));
            })
            ->with('category')
            ->orderBy('category_id')
            ->orderBy('display_order')
            ->orderBy('id')
            ->get();

        return MenuItemResource::collection($items)->response();
    }

    public function store(StoreMenuItemRequest $request): JsonResponse
    {
        $item = MenuItem::create($request->validated());

        return response()->json([
            'data' => MenuItemResource::make($item->load('category')),
            'message' => 'Item created.',
        ], 201);
    }

    public function show(MenuItem $item): JsonResponse
    {
        return response()->json([
            'data' => MenuItemResource::make($item->load('category')),
        ]);
    }

    public function update(UpdateMenuItemRequest $request, MenuItem $item): JsonResponse
    {
        $item->update($request->validated());

        return response()->json([
            'data' => MenuItemResource::make($item->fresh()->load('category')),
            'message' => 'Item updated.',
        ]);
    }

    public function destroy(MenuItem $item): JsonResponse
    {
        $item->delete(); // soft delete

        return response()->json(['message' => 'Item deleted.']);
    }

    public function toggleAvailability(Request $request, MenuItem $item): JsonResponse
    {
        $request->validate(['is_available' => ['sometimes', 'boolean']]);

        $item->is_available = $request->has('is_available')
            ? $request->boolean('is_available')
            : ! $item->is_available;
        $item->save();

        return response()->json([
            'data' => MenuItemResource::make($item),
            'message' => 'Availability updated.',
        ]);
    }

    public function reorder(ReorderRequest $request): JsonResponse
    {
        $order = collect($request->validated('order'));
        $ids = $order->pluck('id');

        $ownedIds = MenuItem::whereIn('id', $ids)->pluck('id');
        if ($ownedIds->count() !== $ids->unique()->count()) {
            return response()->json(['message' => 'One or more items were not found.'], 422);
        }

        DB::transaction(function () use ($order) {
            foreach ($order as $row) {
                MenuItem::whereKey($row['id'])->update(['display_order' => $row['display_order']]);
            }
        });

        return response()->json(['message' => 'Items reordered.']);
    }
}

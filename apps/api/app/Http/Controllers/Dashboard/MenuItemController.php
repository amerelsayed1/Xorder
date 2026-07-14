<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\ReorderRequest;
use App\Http\Requests\Dashboard\StoreMenuItemRequest;
use App\Http\Requests\Dashboard\UpdateMenuItemRequest;
use App\Http\Resources\MenuItemResource;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Services\PlanLimitService;
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
                $term = '%'.$request->string('search').'%';
                $q->where(fn ($q) => $q->where('name_en', 'like', $term)->orWhere('name_ar', 'like', $term));
            })
            ->with('category')
            ->orderBy('category_id')
            ->orderBy('display_order')
            ->orderBy('id')
            ->get();

        return MenuItemResource::collection($items)->response();
    }

    public function store(StoreMenuItemRequest $request, PlanLimitService $limits): JsonResponse
    {
        if (($limit = $limits->itemLimitReached($request->user()->restaurant)) !== null) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_items', ['limit' => $limit]),
            ], 422);
        }

        $data = $request->validated();
        $groups = $data['option_groups'] ?? [];
        unset($data['option_groups']);

        $item = DB::transaction(function () use ($data, $groups) {
            $item = MenuItem::create($data);
            $this->syncOptionGroups($item, $groups);

            return $item;
        });

        return response()->json([
            'data' => MenuItemResource::make($item->load('category', 'optionGroups.options')),
            'message' => __('xorder.messages.item_created'),
        ], 201);
    }

    public function show(MenuItem $item): JsonResponse
    {
        return response()->json([
            'data' => MenuItemResource::make($item->load('category', 'optionGroups.options')),
        ]);
    }

    public function update(UpdateMenuItemRequest $request, MenuItem $item): JsonResponse
    {
        $data = $request->validated();
        $groups = $data['option_groups'] ?? null;
        unset($data['option_groups']);

        DB::transaction(function () use ($item, $data, $groups) {
            $item->update($data);
            // Only resync when the client actually sent the option_groups key.
            if ($groups !== null) {
                $this->syncOptionGroups($item, $groups);
            }
        });

        return response()->json([
            'data' => MenuItemResource::make($item->fresh()->load('category', 'optionGroups.options')),
            'message' => __('xorder.messages.item_updated'),
        ]);
    }

    /**
     * Replace an item's option groups + options with the supplied structure.
     * Simplest correct sync for a small per-item set: wipe and recreate.
     */
    private function syncOptionGroups(MenuItem $item, array $groups): void
    {
        // Clean delete (no orderBy → valid on Postgres); FK cascade removes options.
        OptionGroup::where('menu_item_id', $item->id)->delete();

        foreach (array_values($groups) as $gi => $g) {
            $group = $item->optionGroups()->create([
                'name_en' => $g['name_en'] ?? null,
                'name_ar' => $g['name_ar'] ?? null,
                'is_required' => $g['is_required'] ?? false,
                'max_select' => $g['max_select'] ?? 1,
                'sort_order' => $gi,
            ]);

            foreach (array_values($g['options'] ?? []) as $oi => $o) {
                $group->options()->create([
                    'name_en' => $o['name_en'] ?? null,
                    'name_ar' => $o['name_ar'] ?? null,
                    'price' => $o['price'] ?? 0,
                    'is_available' => $o['is_available'] ?? true,
                    'sort_order' => $oi,
                ]);
            }
        }
    }

    public function destroy(MenuItem $item): JsonResponse
    {
        $item->delete(); // soft delete

        return response()->json(['message' => __('xorder.messages.item_deleted')]);
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
            'message' => __('xorder.messages.availability_updated'),
        ]);
    }

    public function reorder(ReorderRequest $request): JsonResponse
    {
        $order = collect($request->validated('order'));
        $ids = $order->pluck('id');

        $ownedIds = MenuItem::whereIn('id', $ids)->pluck('id');
        if ($ownedIds->count() !== $ids->unique()->count()) {
            return response()->json(['message' => __('xorder.messages.items_not_found')], 422);
        }

        DB::transaction(function () use ($order) {
            foreach ($order as $row) {
                MenuItem::whereKey($row['id'])->update(['display_order' => $row['display_order']]);
            }
        });

        return response()->json(['message' => __('xorder.messages.items_reordered')]);
    }
}

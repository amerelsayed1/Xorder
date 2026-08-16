<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\BulkDeleteItemsRequest;
use App\Http\Requests\Dashboard\ReorderRequest;
use App\Http\Requests\Dashboard\StoreMenuItemRequest;
use App\Http\Requests\Dashboard\UpdateMenuItemRequest;
use App\Http\Resources\MenuItemResource;
use App\Models\MenuItem;
use App\Models\OptionGroup;
use App\Models\Restaurant;
use App\Services\PlanLimitService;
use App\Services\VariantPricingService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class MenuItemController extends Controller
{
    public function __construct(private readonly VariantPricingService $pricing) {}

    public function index(Request $request): JsonResponse
    {
        $items = MenuItem::query()
            // Items of an inactive category are hidden from the management view,
            // mirroring the public menu (see PublicMenuService).
            ->whereHas('category', fn ($q) => $q->where('is_active', true))
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
        $restaurant = $request->user()->restaurant;

        $data = $request->validated();
        $groups = $data['option_groups'] ?? [];
        unset($data['option_groups']);

        // Limit check + insert are serialized per tenant under a row lock so
        // concurrent creates cannot all slip past the plan's item cap (TOCTOU).
        $result = DB::transaction(function () use ($restaurant, $limits, $data, $groups) {
            Restaurant::whereKey($restaurant->getKey())->lockForUpdate()->first();

            if (($limit = $limits->itemLimitReached($restaurant)) !== null) {
                return ['limit' => $limit];
            }

            $item = MenuItem::create($data);
            $this->syncOptionGroups($item, $groups);
            // A size group prices the item, so the submitted price is only a
            // placeholder — replace it with the default size's own figures.
            $this->pricing->syncItem($item);

            return ['item' => $item];
        });

        if (isset($result['limit'])) {
            return response()->json([
                'message' => __('xorder.messages.plan_limit_items', ['limit' => $result['limit']]),
            ], 422);
        }

        $item = $result['item'];

        return response()->json([
            'data' => MenuItemResource::make($item->load('category', 'optionGroups.options', 'sharedOptionGroups.options')),
            'message' => __('xorder.messages.item_created'),
        ], 201);
    }

    public function show(MenuItem $item): JsonResponse
    {
        return response()->json([
            'data' => MenuItemResource::make($item->load('category', 'optionGroups.options', 'sharedOptionGroups.options')),
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
                $item->unsetRelation('optionGroups')->unsetRelation('sharedOptionGroups');
            }
            // Unconditional: a partial update that touches only `price` must
            // still lose to the sizes on an item those sizes already price.
            $this->pricing->syncItem($item);
        });

        return response()->json([
            'data' => MenuItemResource::make($item->fresh()->load('category', 'optionGroups.options', 'sharedOptionGroups.options')),
            'message' => __('xorder.messages.item_updated'),
        ]);
    }

    /**
     * Replace an item's option groups with the supplied ordered list. Each entry
     * is either an inline group (typed for this item) or a reference to a global
     * group from the shared library (`ref: 'shared'` + `option_group_id`). The
     * array index is the unified display position for both flavours.
     *
     * Inline groups are wiped and recreated (simplest correct sync for a small
     * per-item set). Global groups are never touched here — they live in the
     * library and are only attached/detached via the pivot, so edits to a shared
     * group stay live across every item that uses it.
     */
    private function syncOptionGroups(MenuItem $item, array $entries): void
    {
        $entries = array_values($entries);

        // Resolve which referenced ids are real global groups in this tenant, in
        // one query — a client cannot attach a foreign or inline group's id.
        $referencedIds = collect($entries)
            ->filter(fn ($g) => ($g['ref'] ?? 'inline') === 'shared')
            ->pluck('option_group_id')
            ->filter()
            ->map(fn ($id) => (int) $id);

        $validGlobalIds = $referencedIds->isEmpty()
            ? collect()
            : OptionGroup::global()->whereIn('id', $referencedIds)->pluck('id')->flip();

        // Clean delete of inline groups (no orderBy → valid on Postgres); FK
        // cascade removes their options. Global groups (menu_item_id null) are
        // outside this filter and untouched.
        OptionGroup::where('menu_item_id', $item->id)->delete();

        $pivot = [];

        foreach ($entries as $i => $g) {
            if (($g['ref'] ?? 'inline') === 'shared') {
                $groupId = (int) ($g['option_group_id'] ?? 0);
                if ($validGlobalIds->has($groupId)) {
                    $pivot[$groupId] = [
                        'sort_order' => $i,
                        'restaurant_id' => $item->restaurant_id,
                    ];
                }

                continue;
            }

            // A variant (size/portion) group is always single-select and must be
            // chosen — the chosen option sets the item price, so "no size" makes
            // no sense. Force those invariants regardless of what the client sent.
            $isVariant = (bool) ($g['is_variant'] ?? false);

            $group = $item->optionGroups()->create([
                'is_global' => false,
                'name_en' => $g['name_en'] ?? null,
                'name_ar' => $g['name_ar'] ?? null,
                'is_required' => $isVariant ? true : ($g['is_required'] ?? false),
                'is_variant' => $isVariant,
                'max_select' => $isVariant ? 1 : ($g['max_select'] ?? 1),
                'sort_order' => $i,
            ]);

            foreach (array_values($g['options'] ?? []) as $oi => $o) {
                $group->options()->create([
                    'name_en' => $o['name_en'] ?? null,
                    'name_ar' => $o['name_ar'] ?? null,
                    'price' => $o['price'] ?? 0,
                    // A sale price only means anything on a variant group, where
                    // the option IS the item price. On an add-on group the price
                    // is a delta, so drop any discount the client sent.
                    'discounted_price' => $isVariant ? ($o['discounted_price'] ?? null) : null,
                    'is_available' => $o['is_available'] ?? true,
                    'sort_order' => $oi,
                ]);
            }
        }

        // Attach/detach global groups to match the payload (pivot sort_order
        // shares the same index sequence as inline groups above).
        $item->sharedOptionGroups()->sync($pivot);
    }

    public function destroy(MenuItem $item): JsonResponse
    {
        $item->delete(); // soft delete

        return response()->json(['message' => __('xorder.messages.item_deleted')]);
    }

    /**
     * Soft-delete several items at once. Every id is verified against the
     * tenant scope first (same guard as reorder()), so a client cannot delete
     * items outside its restaurant by injecting foreign ids into the list.
     */
    public function bulkDestroy(BulkDeleteItemsRequest $request): JsonResponse
    {
        $ids = collect($request->validated('ids'))->unique();

        $ownedIds = MenuItem::whereIn('id', $ids)->pluck('id');
        if ($ownedIds->count() !== $ids->count()) {
            return response()->json(['message' => __('xorder.messages.items_not_found')], 422);
        }

        MenuItem::whereIn('id', $ownedIds)->delete(); // soft delete

        return response()->json([
            'message' => trans_choice('xorder.messages.items_deleted', $ownedIds->count(), ['count' => $ownedIds->count()]),
        ]);
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

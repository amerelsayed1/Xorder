<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreOptionGroupRequest;
use App\Http\Requests\Dashboard\UpdateOptionGroupRequest;
use App\Http\Resources\OptionGroupResource;
use App\Models\OptionGroup;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

/**
 * The shared "extras" library — reusable option groups a restaurant defines once
 * and attaches to many items. Only global groups (is_global = true) are managed
 * here; inline per-item groups stay part of the menu-item endpoints.
 *
 * Edits are live/shared: changing a group here instantly changes it on every
 * item that references it, because items link to the same row via the pivot.
 */
class OptionGroupController extends Controller
{
    public function index(): JsonResponse
    {
        $groups = OptionGroup::global()
            ->withCount('menuItems')
            ->with(['options', 'categories:id,name_ar,name_en'])
            ->orderBy('name_en')
            ->orderBy('name_ar')
            ->orderBy('id')
            ->get();

        return OptionGroupResource::collection($groups)->response();
    }

    public function store(StoreOptionGroupRequest $request): JsonResponse
    {
        $group = DB::transaction(function () use ($request) {
            $group = $this->makeGroup($request->validated());
            $this->syncOptions($group, $request->validated('options') ?? []);
            $this->syncScope($group, $request->validated());

            return $group;
        });

        return response()->json([
            'data' => OptionGroupResource::make($group->load('options', 'categories:id,name_ar,name_en')->loadCount('menuItems')),
            'message' => __('xorder.messages.option_group_created'),
        ], 201);
    }

    public function show(OptionGroup $optionGroup): JsonResponse
    {
        $this->assertGlobal($optionGroup);

        return response()->json([
            'data' => OptionGroupResource::make($optionGroup->load('options', 'categories:id,name_ar,name_en')->loadCount('menuItems')),
        ]);
    }

    public function update(UpdateOptionGroupRequest $request, OptionGroup $optionGroup): JsonResponse
    {
        $this->assertGlobal($optionGroup);

        DB::transaction(function () use ($request, $optionGroup) {
            $data = $request->validated();
            $isVariant = (bool) ($data['is_variant'] ?? $optionGroup->is_variant);

            $optionGroup->update([
                'name_en' => $data['name_en'] ?? $optionGroup->name_en,
                'name_ar' => $data['name_ar'] ?? $optionGroup->name_ar,
                'is_required' => $isVariant ? true : ($data['is_required'] ?? $optionGroup->is_required),
                'is_variant' => $isVariant,
                'max_select' => $isVariant ? 1 : ($data['max_select'] ?? $optionGroup->max_select),
            ]);

            // Only resync options when the client actually sent the key.
            if (array_key_exists('options', $data)) {
                $this->syncOptions($optionGroup, $data['options'] ?? []);
            }

            // Only reshape scope when the client actually sent it (partial update).
            if (array_key_exists('apply_scope', $data)) {
                $this->syncScope($optionGroup, $data);
            }
        });

        return response()->json([
            'data' => OptionGroupResource::make($optionGroup->fresh()->load('options', 'categories:id,name_ar,name_en')->loadCount('menuItems')),
            'message' => __('xorder.messages.option_group_updated'),
        ]);
    }

    /**
     * Delete a shared group. The menu_item_option_group pivot rows cascade away,
     * so every item that used it simply loses the extra — matching the live,
     * shared nature of the library.
     */
    public function destroy(OptionGroup $optionGroup): JsonResponse
    {
        $this->assertGlobal($optionGroup);

        $optionGroup->delete(); // options + pivot rows cascade via FK

        return response()->json(['message' => __('xorder.messages.option_group_deleted')]);
    }

    /** Create the global group shell, forcing the variant invariants. */
    private function makeGroup(array $data): OptionGroup
    {
        $isVariant = (bool) ($data['is_variant'] ?? false);

        // restaurant_id is stamped by the BelongsToRestaurant trait.
        return OptionGroup::create([
            'menu_item_id' => null,
            'is_global' => true,
            'apply_scope' => $data['apply_scope'] ?? OptionGroup::SCOPE_ITEMS,
            'name_en' => $data['name_en'] ?? null,
            'name_ar' => $data['name_ar'] ?? null,
            'is_required' => $isVariant ? true : ($data['is_required'] ?? false),
            'is_variant' => $isVariant,
            'max_select' => $isVariant ? 1 : ($data['max_select'] ?? 1),
            'sort_order' => 0,
        ]);
    }

    /**
     * Apply the group's scope. Category links are kept only for the "categories"
     * scope; switching to "all"/"items" clears them. Leaving the per-item
     * "items" scope also detaches any item pivots, so a group only ever applies
     * through one path at a time.
     */
    private function syncScope(OptionGroup $group, array $data): void
    {
        $scope = $data['apply_scope'] ?? $group->apply_scope ?? OptionGroup::SCOPE_ITEMS;
        $group->update(['apply_scope' => $scope]);

        if ($scope === OptionGroup::SCOPE_CATEGORIES) {
            // Category ids are already validated as tenant-owned by the request.
            $group->categories()->sync($data['category_ids'] ?? []);
        } else {
            $group->categories()->detach();
        }

        if ($scope !== OptionGroup::SCOPE_ITEMS) {
            // Auto-applied groups don't use the per-item pivot; drop stale links.
            $group->menuItems()->detach();
        }
    }

    /** Wipe and recreate a group's options (small set, simplest correct sync). */
    private function syncOptions(OptionGroup $group, array $options): void
    {
        $group->options()->delete();

        foreach (array_values($options) as $oi => $o) {
            $group->options()->create([
                'name_en' => $o['name_en'] ?? null,
                'name_ar' => $o['name_ar'] ?? null,
                'price' => $o['price'] ?? 0,
                'is_available' => $o['is_available'] ?? true,
                'sort_order' => $oi,
            ]);
        }
    }

    /**
     * Guard: the library endpoints only ever act on global groups. An inline
     * per-item group's id (still tenant-owned, so route binding resolves it)
     * must not be editable/deletable here → treat it as not found.
     */
    private function assertGlobal(OptionGroup $group): void
    {
        abort_unless($group->is_global, 404);
    }
}

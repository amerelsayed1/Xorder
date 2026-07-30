<?php

namespace App\Http\Controllers\Dashboard;

use App\Http\Controllers\Controller;
use App\Http\Requests\Dashboard\StoreComboRequest;
use App\Http\Requests\Dashboard\UpdateComboRequest;
use App\Http\Resources\ComboResource;
use App\Models\Combo;
use App\Models\ComboGroup;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class ComboController extends Controller
{
    public function index(): JsonResponse
    {
        $combos = Combo::with('groups.items.menuItem')
            ->orderBy('sort_order')->orderBy('id')->get();

        return ComboResource::collection($combos)->response();
    }

    public function store(StoreComboRequest $request): JsonResponse
    {
        $data = $request->validated();
        $groups = $data['groups'] ?? [];
        unset($data['groups']);

        $combo = DB::transaction(function () use ($data, $groups) {
            $combo = Combo::create($data);
            $this->syncGroups($combo, $groups);

            return $combo;
        });

        return response()->json([
            'data' => ComboResource::make($combo->load('groups.items.menuItem')),
            'message' => __('xorder.messages.combo_created'),
        ], 201);
    }

    public function update(UpdateComboRequest $request, Combo $combo): JsonResponse
    {
        $data = $request->validated();
        $groups = $data['groups'] ?? null;
        unset($data['groups']);

        DB::transaction(function () use ($combo, $data, $groups) {
            $combo->update($data);
            if ($groups !== null) {
                $this->syncGroups($combo, $groups);
            }
        });

        return response()->json([
            'data' => ComboResource::make($combo->fresh()->load('groups.items.menuItem')),
            'message' => __('xorder.messages.combo_updated'),
        ]);
    }

    public function destroy(Combo $combo): JsonResponse
    {
        $combo->delete();

        return response()->json(['message' => __('xorder.messages.combo_deleted')]);
    }

    public function toggleStatus(Request $request, Combo $combo): JsonResponse
    {
        $request->validate(['is_active' => ['sometimes', 'boolean']]);

        $combo->is_active = $request->has('is_active')
            ? $request->boolean('is_active')
            : ! $combo->is_active;
        $combo->save();

        return response()->json([
            'data' => ComboResource::make($combo->load('groups.items.menuItem')),
            'message' => __('xorder.messages.combo_updated'),
        ]);
    }

    private function syncGroups(Combo $combo, array $groups): void
    {
        ComboGroup::where('combo_id', $combo->id)->delete();

        foreach (array_values($groups) as $gi => $g) {
            // A variant (size/portion) group is single-select — the chosen item
            // sets the combo price, so picking two makes no sense.
            $isVariant = (bool) ($g['is_variant'] ?? false);

            $group = $combo->groups()->create([
                'name_en' => $g['name_en'] ?? null,
                'name_ar' => $g['name_ar'] ?? null,
                'max_select' => $isVariant ? 1 : ($g['max_select'] ?? 1),
                'is_variant' => $isVariant,
                'sort_order' => $gi,
            ]);

            foreach (array_values($g['items'] ?? []) as $ii => $it) {
                $group->items()->create([
                    'menu_item_id' => $it['menu_item_id'],
                    'extra_price' => $it['extra_price'] ?? 0,
                    'sort_order' => $ii,
                ]);
            }
        }
    }
}

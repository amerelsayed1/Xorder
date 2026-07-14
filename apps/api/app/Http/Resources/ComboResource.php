<?php

namespace App\Http\Resources;

use App\Models\Combo;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Combo */
class ComboResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'image_url' => $this->image_url,
            'base_price' => $this->base_price,
            'is_active' => $this->is_active,
            'sort_order' => $this->sort_order,
            'groups' => $this->whenLoaded('groups', fn () => $this->groups->map(fn ($g) => [
                'id' => $g->id,
                'name_en' => $g->name_en,
                'name_ar' => $g->name_ar,
                'max_select' => $g->max_select,
                'items' => $g->items->map(fn ($it) => [
                    'id' => $it->id,
                    'menu_item_id' => $it->menu_item_id,
                    'extra_price' => $it->extra_price,
                    'item_name_en' => $it->menuItem?->name_en,
                    'item_name_ar' => $it->menuItem?->name_ar,
                ])->values(),
            ])->values()),
        ];
    }
}

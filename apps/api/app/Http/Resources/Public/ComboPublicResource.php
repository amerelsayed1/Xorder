<?php

namespace App\Http\Resources\Public;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public combo/offer shape for the guest menu.
 *
 * @mixin \App\Models\Combo
 */
class ComboPublicResource extends JsonResource
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
            'groups' => $this->whenLoaded('groups', fn () => $this->groups->map(fn ($g) => [
                'name_en' => $g->name_en,
                'name_ar' => $g->name_ar,
                'max_select' => $g->max_select,
                'items' => $g->items->map(fn ($it) => [
                    'name_en' => $it->menuItem?->name_en,
                    'name_ar' => $it->menuItem?->name_ar,
                    'extra_price' => $it->extra_price,
                ])->values(),
            ])->values()),
        ];
    }
}

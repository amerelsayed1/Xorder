<?php

namespace App\Http\Resources\Public;

use App\Models\MenuItem;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * Public, customer-facing item shape. Exposes only menu data — no internal
 * ids beyond what the page needs, no timestamps, no tenant internals.
 *
 * @mixin MenuItem
 */
class MenuItemPublicResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'name_ar' => $this->name_ar,
            'name_en' => $this->name_en,
            'description_ar' => $this->description_ar,
            'description_en' => $this->description_en,
            'price' => $this->price,
            'discounted_price' => $this->discounted_price,
            'image_url' => $this->image_url,
            'is_available' => $this->is_available,
            'is_featured' => $this->is_featured,
            'option_groups' => $this->whenLoaded('optionGroups', fn () => $this->optionGroups->map(fn ($g) => [
                'name_en' => $g->name_en,
                'name_ar' => $g->name_ar,
                'is_required' => $g->is_required,
                'max_select' => $g->max_select,
                'options' => $g->options->where('is_available', true)->map(fn ($o) => [
                    'name_en' => $o->name_en,
                    'name_ar' => $o->name_ar,
                    'price' => $o->price,
                ])->values(),
            ])->values()),
        ];
    }
}
